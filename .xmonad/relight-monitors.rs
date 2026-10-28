#!/usr/bin/env rust-script
//! Relight a monitor when it comes back, and unblock the compositor when X
//! gets its virtual terminal back.
//!
//! When a DisplayPort monitor reconnects (powered back on, or the KVM switches
//! it back), the NVIDIA X driver notices but does not drive it again, so the
//! screen stays black until a VT switch forces a modeset. This watches the
//! outputs and, a second after one reconnects, either re-trains its link with a
//! DPMS cycle (it still has its mode) or sets its last mode again (it came back
//! without one). Neither takes an active output out of the screen, so GTK apps
//! keep their scale.
//!
//! After a VT switch the screen can stay black with only the cursor: the
//! NVIDIA driver never completes a SYNC fence trigger that the compositor sent
//! while X was in the background, and picom waits for its render fence without
//! a bound (picom#1527), so it paints nothing until some other client draws.
//! Any client may trigger a fence, so shortly after X's VT comes back to the
//! front this triggers the compositor's fences, which releases it.
//!
//!     relight-monitors          watch (started from .xinitrc)
//!     relight-monitors status   every output with its layout
//!     relight-monitors now      xrandr off and on for every lit output
//!     relight-monitors unblock  trigger the compositor's fences once
//!     relight-monitors vt       only the VT part of the watch, for testing
//!
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! libc = "0.2"
//! x11rb = { version = "0.14", features = ["randr", "dpms", "res", "sync"] }
//! ```
use std::collections::BTreeMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::os::fd::{AsRawFd, RawFd};
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use x11rb::connection::Connection;
use x11rb::protocol::dpms::{ConnectionExt as _, DPMSMode};
use x11rb::protocol::randr::{self, ConnectionExt as _, NotifyMask};
use x11rb::protocol::res::{self, ConnectionExt as _};
use x11rb::protocol::sync::ConnectionExt as _;
use x11rb::protocol::xproto::{AtomEnum, ConnectionExt as _, Window};
use x11rb::rust_connection::RustConnection;

/// How long after a reconnect to act, then how long to wait before each retry.
const SETTLE: [Duration; 3] = [Duration::from_secs(1), Duration::from_secs(2), Duration::from_secs(3)];

/// When to unblock the compositor after X's VT comes back: once X has taken the
/// display back, and once more for a frame caught in between.
const UNBLOCK: [Duration; 2] = [Duration::from_millis(300), Duration::from_millis(1500)];

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

/// What woke the watcher up.
struct Woke {
    console: bool,
}

struct Screen {
    conn: RustConnection,
    root: Window,
    number: usize,
}

impl Screen {
    fn open() -> Result<Self> {
        let (conn, number) = x11rb::connect(None).context("connecting to the X server")?;
        let root = conn.setup().roots[number].root;
        Ok(Self { conn, root, number })
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

    /// Waits for a `RandR` event, a VT switch (`console` signals it with
    /// POLLPRI) or the timeout, then drains the X queue. Which X event does not
    /// matter: the outputs are read afresh afterwards.
    fn wait(&self, console: Option<RawFd>, timeout: Option<Duration>) -> Result<Woke> {
        let mut woke = Woke { console: false };
        if self.conn.poll_for_event()?.is_none() {
            woke.console = wait_readable(self.conn.stream().as_raw_fd(), console, timeout);
        }
        while self.conn.poll_for_event()?.is_some() {}
        Ok(woke)
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

    /// The VT this X server runs on, from the `XFree86_VT` root property (Xorg).
    fn vt(&self) -> Result<Option<u32>> {
        let atom = self.conn.intern_atom(true, b"XFree86_VT")?.reply()?.atom;
        if atom == 0 {
            return Ok(None);
        }
        let prop = self.conn.get_property(false, self.root, atom, AtomEnum::INTEGER, 0, 1)?.reply()?;
        Ok(prop.value32().and_then(|mut values| values.next()).filter(|&vt| vt > 0))
    }

    /// Triggers every SYNC fence of the compositor (the owner of
    /// `_NET_WM_CM_Sn`) and says how many. A compositor that was not waiting
    /// loses at most one frame's ordering against other clients' rendering.
    fn unblock_compositor(&self) -> Result<usize> {
        let selection = format!("_NET_WM_CM_S{}", self.number);
        let selection = self.conn.intern_atom(false, selection.as_bytes())?.reply()?.atom;
        let owner = self.conn.get_selection_owner(selection)?.reply()?.owner;
        if owner == 0 {
            return Ok(0);
        }
        self.conn.res_query_version(1, 2)?.reply()?;
        self.conn.sync_initialize(3, 1)?.reply()?;
        let every = res::ResourceIdSpec { resource: 0, type_: 0 };
        let resources = self.conn.res_query_resource_bytes(owner, &[every])?.reply()?;
        // X-Resource names resource types by atoms it creates on first use.
        let fence_type = self.conn.intern_atom(false, b"SyncFence")?.reply()?.atom;
        let fences: Vec<u32> = resources
            .sizes
            .iter()
            .map(|value| value.size.spec)
            .filter(|spec| spec.type_ == fence_type)
            .map(|spec| spec.resource)
            .collect();
        for &fence in &fences {
            // The compositor may free a fence meanwhile; that error is harmless.
            self.conn.sync_trigger_fence(fence)?.ignore_error();
        }
        self.conn.flush()?;
        Ok(fences.len())
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

/// Waits until the X connection is readable, the console signals a switch or
/// the timeout passes, and says whether the console did.
fn wait_readable(x: RawFd, console: Option<RawFd>, timeout: Option<Duration>) -> bool {
    let mut fds = [
        libc::pollfd { fd: x, events: libc::POLLIN, revents: 0 },
        // poll skips a negative fd
        libc::pollfd { fd: console.unwrap_or(-1), events: libc::POLLPRI | libc::POLLERR, revents: 0 },
    ];
    let millis = timeout.map_or(-1, |t| i32::try_from(t.as_millis()).unwrap_or(i32::MAX));
    // SAFETY: fds is a valid array of two pollfds for the whole call
    unsafe { libc::poll(fds.as_mut_ptr(), 2, millis) };
    fds[1].revents != 0
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

/// Follows which VT is in front (/sys/class/tty/tty0/active signals every
/// switch with POLLPRI) and unblocks the compositor shortly after X's own VT
/// comes back.
struct VtWatch {
    active: File,
    x_tty: String,
    in_front: bool,
    unblock_at: Vec<Instant>,
}

impl VtWatch {
    /// `None` when this X server runs on no VT.
    fn new(screen: &Screen) -> Result<Option<Self>> {
        let Some(vt) = screen.vt()? else { return Ok(None) };
        let path = "/sys/class/tty/tty0/active";
        let active = File::open(path).with_context(|| format!("opening {path}"))?;
        let mut watch = Self { active, x_tty: format!("tty{vt}"), in_front: true, unblock_at: Vec::new() };
        watch.in_front = watch.front()? == watch.x_tty;
        Ok(Some(watch))
    }

    fn fd(&self) -> RawFd {
        self.active.as_raw_fd()
    }

    /// The VT in front; reading also re-arms the POLLPRI notification.
    fn front(&mut self) -> Result<String> {
        let mut name = String::new();
        self.active.seek(SeekFrom::Start(0))?;
        self.active.read_to_string(&mut name)?;
        Ok(name.trim().to_owned())
    }

    fn next_due(&self) -> Option<Instant> {
        self.unblock_at.iter().copied().min()
    }

    /// After a POLLPRI. A switch between two other VTs changes nothing.
    fn note_switch(&mut self) -> Result<()> {
        let in_front = self.front()? == self.x_tty;
        if in_front == self.in_front {
            return Ok(());
        }
        self.in_front = in_front;
        if in_front {
            println!("{} is in front again", self.x_tty);
            let now = Instant::now();
            self.unblock_at = UNBLOCK.iter().map(|delay| now + *delay).collect();
        } else {
            println!("{} left the front", self.x_tty);
            self.unblock_at.clear();
        }
        Ok(())
    }

    fn unblock_due(&mut self, screen: &Screen) {
        let now = Instant::now();
        if !self.unblock_at.iter().any(|&at| at <= now) {
            return;
        }
        self.unblock_at.retain(|&at| at > now);
        match screen.unblock_compositor() {
            Ok(fences) => println!("unblock the compositor: triggered {fences} sync fence(s)"),
            Err(err) => println!("could not unblock the compositor: {err:#}"),
        }
    }
}

struct Retry {
    at: Instant,
    attempt: usize,
}

struct Watcher {
    screen: Screen,
    vt: Option<VtWatch>,
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
        let vt = VtWatch::new(&screen)?;
        let tty = vt.as_ref().map_or_else(String::new, |vt| format!(" and {}", vt.x_tty));
        println!("watching {}{tty}", watched.join(", "));
        Ok(Self { screen, vt, connected, remembered, pending: BTreeMap::new() })
    }

    fn run(mut self) -> Result<()> {
        loop {
            let console = self.vt.as_ref().map(VtWatch::fd);
            if self.screen.wait(console, self.next_due())?.console {
                if let Some(vt) = self.vt.as_mut() {
                    vt.note_switch()?;
                }
            }
            self.note_changes()?;
            self.relight_due()?;
            if let Some(vt) = self.vt.as_mut() {
                vt.unblock_due(&self.screen);
            }
        }
    }

    fn next_due(&self) -> Option<Duration> {
        let now = Instant::now();
        let unblock = self.vt.as_ref().and_then(VtWatch::next_due);
        self.pending.values().map(|r| r.at).chain(unblock).map(|at| at.saturating_duration_since(now)).min()
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

/// The VT part of the watch alone, to test it beside a running watcher.
fn watch_vt(screen: &Screen) -> Result<()> {
    let mut vt = VtWatch::new(screen)?.context("this X server runs on no VT")?;
    println!("watching {}", vt.x_tty);
    loop {
        let timeout = vt.next_due().map(|at| at.saturating_duration_since(Instant::now()));
        if screen.wait(Some(vt.fd()), timeout)?.console {
            vt.note_switch()?;
        }
        vt.unblock_due(screen);
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
        Some("unblock") => {
            println!("triggered {} sync fence(s)", screen.unblock_compositor()?);
            Ok(())
        }
        Some("vt") => watch_vt(&screen),
        Some(other) => bail!("unknown command {other:?}; use status, now, unblock or vt"),
    }
}
