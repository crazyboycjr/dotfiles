#!/usr/bin/env rust-script
//! Relight a monitor when it comes back.
//!
//! When a DisplayPort monitor reconnects (powered back on, or the KVM switches
//! it back), the NVIDIA X driver notices but does not drive it again, so the
//! screen stays black until a VT switch forces a modeset. This watches the
//! outputs and, a second after one reconnects, either re-trains its link with a
//! DPMS cycle (it still has its mode) or sets its last mode again (it came back
//! without one). Neither takes an active output out of the screen, so GTK apps
//! keep their scale.
//!
//!     relight-monitors          watch (started from .xinitrc)
//!     relight-monitors status   every output with its layout
//!     relight-monitors now      xrandr off and on for every lit output
//!
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! libc = "0.2"
//! x11rb = { version = "0.14", features = ["randr", "dpms"] }
//! ```
use std::collections::BTreeMap;
use std::os::fd::AsRawFd;
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use x11rb::connection::Connection;
use x11rb::protocol::dpms::{ConnectionExt as _, DPMSMode};
use x11rb::protocol::randr::{self, ConnectionExt as _, NotifyMask};
use x11rb::protocol::xproto::Window;
use x11rb::rust_connection::RustConnection;

/// How long after a reconnect to act, then how long to wait before each retry.
const SETTLE: [Duration; 3] = [Duration::from_secs(1), Duration::from_secs(2), Duration::from_secs(3)];

/// Where an output was last driven; enough to drive it there again.
#[derive(Clone, Debug)]
struct Layout {
    mode: String,
    rate: f64,
    x: i16,
    y: i16,
    rotation: &'static str,
    primary: bool,
}

impl Layout {
    fn xrandr_args(&self, output: &str) -> Vec<String> {
        let mut args = vec![
            "--output".to_owned(),
            output.to_owned(),
            "--mode".to_owned(),
            self.mode.clone(),
            "--rate".to_owned(),
            format!("{:.2}", self.rate),
            "--pos".to_owned(),
            format!("{}x{}", self.x, self.y),
            "--rotate".to_owned(),
            self.rotation.to_owned(),
        ];
        if self.primary {
            args.push("--primary".to_owned());
        }
        args
    }
}

struct Output {
    name: String,
    connected: bool,
    layout: Option<Layout>,
}

impl Output {
    fn lit(&self) -> bool {
        self.connected && self.layout.is_some()
    }
}

/// What to do for an output that has just reconnected.
enum Relight {
    /// It still has its mode: a DPMS cycle makes the driver train the link again.
    RetrainLink,
    /// It came back without its mode: set the last one again, with no --off first.
    SetMode(Layout),
    /// It was never seen lit: autorandr's detected profile, or a clone of the primary.
    Configure,
}

fn plan(output: &Output, remembered: Option<&Layout>) -> Relight {
    match (&output.layout, remembered) {
        (Some(_), _) => Relight::RetrainLink,
        (None, Some(layout)) => Relight::SetMode(layout.clone()),
        (None, None) => Relight::Configure,
    }
}

struct Screen {
    conn: RustConnection,
    root: Window,
}

impl Screen {
    fn open() -> Result<Self> {
        let (conn, screen) = x11rb::connect(None).context("connecting to the X server")?;
        let root = conn.setup().roots[screen].root;
        Ok(Self { conn, root })
    }

    fn subscribe(&self) -> Result<()> {
        let changes = NotifyMask::OUTPUT_CHANGE | NotifyMask::CRTC_CHANGE | NotifyMask::SCREEN_CHANGE;
        self.conn.randr_select_input(self.root, changes)?.check()?;
        Ok(())
    }

    fn outputs(&self) -> Result<Vec<Output>> {
        let res = self.conn.randr_get_screen_resources_current(self.root)?.reply()?;
        let primary = self.conn.randr_get_output_primary(self.root)?.reply()?.output;
        let modes = mode_names(&res);
        let mut outputs = Vec::new();
        for &output in &res.outputs {
            let info = self.conn.randr_get_output_info(output, res.config_timestamp)?.reply()?;
            let layout = if info.crtc == 0 {
                None
            } else {
                let crtc = self.conn.randr_get_crtc_info(info.crtc, res.config_timestamp)?.reply()?;
                modes.get(&crtc.mode).map(|(mode, rate)| Layout {
                    mode: mode.clone(),
                    rate: *rate,
                    x: crtc.x,
                    y: crtc.y,
                    rotation: rotation_name(u16::from(crtc.rotation)),
                    primary: output == primary,
                })
            };
            outputs.push(Output {
                name: String::from_utf8_lossy(&info.name).into_owned(),
                connected: info.connection == randr::Connection::CONNECTED,
                layout,
            });
        }
        Ok(outputs)
    }

    fn output(&self, name: &str) -> Result<Option<Output>> {
        Ok(self.outputs()?.into_iter().find(|o| o.name == name))
    }

    /// Waits for a RandR event or the timeout, then drains the queue. Which
    /// event arrived does not matter: the outputs are read afresh afterwards.
    fn wait_for_change(&self, timeout: Option<Duration>) -> Result<()> {
        if self.conn.poll_for_event()?.is_none() {
            wait_readable(self.conn.stream().as_raw_fd(), timeout);
        }
        while self.conn.poll_for_event()?.is_some() {}
        Ok(())
    }

    fn relight(&self, name: &str, how: Relight) -> Result<bool> {
        match how {
            Relight::RetrainLink => {
                println!("relight {name}: dpms off, on");
                self.cycle_dpms()?;
                Ok(true)
            }
            Relight::SetMode(layout) => {
                let args = layout.xrandr_args(name);
                println!("relight {name}: {}", args[2..].join(" "));
                Ok(xrandr(&args))
            }
            Relight::Configure => configure(name),
        }
    }

    /// DPMS is normally off here, so it is enabled just for the cycle.
    fn cycle_dpms(&self) -> Result<()> {
        let enabled = self.conn.dpms_info()?.reply()?.state;
        if !enabled {
            self.conn.dpms_enable()?;
        }
        self.conn.dpms_force_level(DPMSMode::OFF)?.check()?;
        thread::sleep(Duration::from_secs(1));
        self.conn.dpms_force_level(DPMSMode::ON)?.check()?;
        if !enabled {
            self.conn.dpms_disable()?;
        }
        self.conn.flush()?;
        Ok(())
    }
}

/// Mode id to (name, refresh rate). Layouts keep the name and rate rather than
/// the id, which the driver renews after a reconnect.
fn mode_names(res: &randr::GetScreenResourcesCurrentReply) -> BTreeMap<u32, (String, f64)> {
    let mut names = BTreeMap::new();
    let mut pos = 0;
    for mode in &res.modes {
        let len = usize::from(mode.name_len);
        let name = String::from_utf8_lossy(&res.names[pos..pos + len]).into_owned();
        pos += len;
        let total = f64::from(mode.htotal) * f64::from(mode.vtotal);
        let rate = if total > 0.0 { f64::from(mode.dot_clock) / total } else { 0.0 };
        names.insert(mode.id, (name, rate));
    }
    names
}

fn rotation_name(rotation: u16) -> &'static str {
    match rotation & 0xF {
        2 => "left",
        4 => "inverted",
        8 => "right",
        _ => "normal",
    }
}

fn wait_readable(fd: i32, timeout: Option<Duration>) {
    let mut fds = [libc::pollfd { fd, events: libc::POLLIN, revents: 0 }];
    let millis = timeout.map_or(-1, |t| i32::try_from(t.as_millis()).unwrap_or(i32::MAX));
    // SAFETY: fds is a valid array of one pollfd for the whole call
    unsafe { libc::poll(fds.as_mut_ptr(), 1, millis) };
}

fn xrandr(args: &[String]) -> bool {
    Command::new("xrandr").args(args).status().is_ok_and(|s| s.success())
}

fn configure(name: &str) -> Result<bool> {
    let detected = Command::new("autorandr").arg("--detected").output()?;
    let profile = String::from_utf8_lossy(&detected.stdout).split_whitespace().next().map(str::to_owned);
    Ok(match profile {
        Some(profile) => {
            println!("{name} connected without a mode, applying autorandr profile {profile}");
            Command::new("autorandr").arg("--change").status()?.success()
        }
        None => {
            println!("{name} connected without a mode, cloning the primary at 0x0");
            xrandr(&["--output", name, "--auto", "--pos", "0x0"].map(str::to_owned))
        }
    })
}

struct Retry {
    at: Instant,
    attempt: usize,
}

struct Watcher {
    screen: Screen,
    connected: BTreeMap<String, bool>,
    remembered: BTreeMap<String, Layout>,
    pending: BTreeMap<String, Retry>,
}

impl Watcher {
    fn new(screen: Screen) -> Result<Self> {
        screen.subscribe()?;
        let outputs = screen.outputs()?;
        let connected = outputs.iter().map(|o| (o.name.clone(), o.connected)).collect();
        let remembered: BTreeMap<_, _> =
            outputs.iter().filter_map(|o| Some((o.name.clone(), o.layout.clone()?))).collect();
        let watched: Vec<String> = outputs
            .iter()
            .filter(|o| o.connected || remembered.contains_key(&o.name))
            .map(|o| format!("{}{}", o.name, if o.connected { "" } else { " (off)" }))
            .collect();
        println!("watching {}", watched.join(", "));
        Ok(Self { screen, connected, remembered, pending: BTreeMap::new() })
    }

    fn run(mut self) -> Result<()> {
        loop {
            self.screen.wait_for_change(self.next_due())?;
            self.note_changes()?;
            self.relight_due()?;
        }
    }

    fn next_due(&self) -> Option<Duration> {
        self.pending.values().map(|r| r.at.saturating_duration_since(Instant::now())).min()
    }

    fn note_changes(&mut self) -> Result<()> {
        for output in self.screen.outputs()? {
            let was = self.connected.insert(output.name.clone(), output.connected).unwrap_or(false);
            match (was, output.connected) {
                (false, true) => {
                    println!("{} reconnected", output.name);
                    self.pending.insert(output.name.clone(), Retry { at: Instant::now() + SETTLE[0], attempt: 0 });
                }
                (true, false) => {
                    println!("{} disconnected", output.name);
                    self.pending.remove(&output.name);
                }
                _ => {}
            }
            let settled = output.connected && !self.pending.contains_key(&output.name);
            if let (true, Some(layout)) = (settled, output.layout) {
                self.remembered.insert(output.name, layout);
            }
        }
        Ok(())
    }

    fn relight_due(&mut self) -> Result<()> {
        let now = Instant::now();
        let due: Vec<String> = self.pending.iter().filter(|(_, r)| r.at <= now).map(|(n, _)| n.clone()).collect();
        for name in due {
            let attempt = self.pending.remove(&name).map_or(0, |r| r.attempt);
            let Some(output) = self.screen.output(&name)?.filter(|o| o.connected) else { continue };
            let ok = self.screen.relight(&name, plan(&output, self.remembered.get(&name)))?;
            let lit = self.screen.output(&name)?.is_some_and(|o| o.lit());
            if ok && lit {
                continue;
            }
            if let Some(delay) = SETTLE.get(attempt + 1) {
                println!("{name} not lit yet, retrying in {} s", delay.as_secs());
                self.pending.insert(name, Retry { at: Instant::now() + *delay, attempt: attempt + 1 });
            }
        }
        Ok(())
    }
}

fn print_status(screen: &Screen) -> Result<()> {
    for output in screen.outputs()?.iter().filter(|o| o.connected || o.layout.is_some()) {
        let state = if output.connected { "connected" } else { "disconnected" };
        match &output.layout {
            Some(layout) => println!("{} {state}: {}", output.name, layout.xrandr_args(&output.name)[2..].join(" ")),
            None => println!("{} {state}: no mode", output.name),
        }
    }
    Ok(())
}

/// The old hard relight: off, then the same mode again, for every lit output.
fn relight_all_now(screen: &Screen) -> Result<()> {
    for output in screen.outputs()?.into_iter().filter(Output::lit) {
        let args = output.layout.as_ref().expect("lit outputs have a layout").xrandr_args(&output.name);
        println!("relight {} hard: {}", output.name, args[2..].join(" "));
        xrandr(&["--output", &output.name, "--off"].map(str::to_owned));
        xrandr(&args);
    }
    Ok(())
}

fn main() -> Result<()> {
    let screen = Screen::open()?;
    match std::env::args().nth(1).as_deref() {
        None => Watcher::new(screen)?.run(),
        Some("status") => print_status(&screen),
        Some("now") => relight_all_now(&screen),
        Some(other) => bail!("unknown command {other:?}; use status or now"),
    }
}
