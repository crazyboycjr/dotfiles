#!/usr/bin/env rust-script
//! Colour schemes for the INNOCN PU15-PRE, the Mac mini's main display.
//!
//! Run bare for the picker window, or `innocn-color list | status | apply <scheme> [K] [brightness%]`
//! (also `apply rgb R G B` for raw linear gains and `apply <file.icc>`). A scheme is macOS's own
//! EDID profile for the panel with a new calibration curve (vcgt) and, for the vivid ones,
//! colorants moved toward sRGB. ColorSync assigns it, and BetterDisplay is told as well, since it
//! re-applies its stored profile whenever the display reconnects.
//!
//! ```cargo
//! [package]
//! edition = "2024"
//!
//! [dependencies]
//! gpui = { package = "gpui-pre", version = "=0.3.4" }
//! gpui_platform = { package = "gpui-pre-platform", version = "=0.3.4", features = ["font-kit", "runtime_shaders"] }
//! gpui-component = { git = "https://github.com/longbridge/gpui-kit", tag = "v0.6.1" }
//! gpui-kit-assets = { git = "https://github.com/longbridge/gpui-kit", tag = "v0.6.1" }
//!
//! [features]
//! # `shot out.png [dark] [scheme]` renders the window headlessly, for reviewing the design.
//! shot = ["gpui/test-support", "gpui_platform/test-support"]
//! ```

use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        Mutex,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

// The schemes. Tune them here.

/// Linear R, G, B gains that make the panel's white match the AW2725Q's (taken as D65), found by
/// photo on 2026-10-25. Every scheme starts from this correction.
const PANEL_CORRECTION: [f64; 3] = [1.00, 0.90, 0.97];

const SCHEMES: [Scheme; 7] = [
    //           id          name       white tone vivid  %   what it is for
    Scheme::new("standard", "标准桌面", 6500, 2.2, 0.0, 100, "日常办公和上网"),
    Scheme::new("warm",     "暖白桌面", 5500, 2.2, 0.0, 100, "白色更柔和，不刺眼"),
    Scheme::new("reading",  "阅读",     5000, 2.2, 0.0,  90, "适合长时间看文字"),
    Scheme::new("night",    "夜读",     3800, 2.2, 0.0,  75, "夜里关了灯看书"),
    Scheme::new("movie",    "电影",     6500, 2.4, 0.0, 100, "暗部更深，适合看电影"),
    Scheme::new("sports",   "运动",     6500, 2.2, 0.5, 100, "颜色更鲜艳，适合看比赛"),
    Scheme::new("game",     "游戏",     6500, 2.0, 0.5, 100, "暗部提亮，颜色更鲜艳"),
];

/// The warmth and brightness sliders' ranges.
const KELVIN_RANGE: (u32, u32) = (2700, 6500);
const PERCENT_RANGE: (u32, u32) = (30, 100);

/// `white` is a colour temperature in kelvin. `tone` is the overall gamma; the panel's own is 2.2.
/// `vivid` moves the profile's colorants from the EDID primaries (0) toward sRGB's (1), so sRGB
/// content stretches into the panel's wider native gamut. `brightness` (percent) scales the
/// curve's channel maxima.
struct Scheme {
    id: &'static str,
    name: &'static str,
    white: u32,
    tone: f64,
    vivid: f64,
    brightness: u32,
    purpose: &'static str,
}

impl Scheme {
    const fn new(
        id: &'static str,
        name: &'static str,
        white: u32,
        tone: f64,
        vivid: f64,
        brightness: u32,
        purpose: &'static str,
    ) -> Self {
        Self { id, name, white, tone, vivid, brightness, purpose }
    }
}

/// A scheme with the sliders' values.
#[derive(Clone, Copy, PartialEq, Debug)]
struct Look {
    scheme: usize,
    kelvin: u32,
    percent: u32,
}

impl Look {
    fn of(scheme: usize) -> Self {
        let s = &SCHEMES[scheme];
        Self { scheme, kelvin: s.white, percent: s.brightness }
    }

    fn describe(&self) -> String {
        format!("{} · {}K · 亮度 {}%", SCHEMES[self.scheme].name, self.kelvin, self.percent)
    }
}

enum Target {
    Look(Look),
    Rgb([f64; 3]),
    File(PathBuf),
}

mod color {
    pub type Vec3 = [f64; 3];
    type Mat3 = [[f64; 3]; 3];

    pub const NATIVE_GAMMA: f64 = 2.2;
    const EDID_PRIMARIES: [(f64, f64); 3] = [(0.6846, 0.3135), (0.2432, 0.7070), (0.1387, 0.0547)];
    /// sRGB's colorants adapted to D50, as in the sRGB IEC61966-2.1 profile.
    pub const SRGB_COLORANTS: [Vec3; 3] =
        [[0.43607, 0.22249, 0.01392], [0.38515, 0.71687, 0.09708], [0.14307, 0.06061, 0.71410]];

    fn xyz((x, y): (f64, f64)) -> Vec3 {
        [x / y, 1.0, (1.0 - x - y) / y]
    }

    fn det(m: &Mat3) -> f64 {
        m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
    }

    fn solve(m: &Mat3, v: Vec3) -> Vec3 {
        let d = det(m);
        [0, 1, 2].map(|k| {
            let mut a = *m;
            for (r, row) in a.iter_mut().enumerate() {
                row[k] = v[r];
            }
            det(&a) / d
        })
    }

    /// Chromaticity of a white of `kelvin`: CIE daylight from 5000 K up, the Planckian locus from
    /// 4000 K down, and a blend between, so the warmth slider has no tint jump at 4000 K.
    pub fn white(kelvin: f64) -> (f64, f64) {
        let s = ((1e6 / 4000.0 - 1e6 / kelvin) / (1e6 / 4000.0 - 1e6 / 5000.0)).clamp(0.0, 1.0);
        if s >= 1.0 {
            daylight(kelvin)
        } else if s <= 0.0 {
            planck(kelvin)
        } else {
            let (d, p) = (daylight(kelvin), planck(kelvin));
            (p.0 + s * (d.0 - p.0), p.1 + s * (d.1 - p.1))
        }
    }

    fn daylight(kelvin: f64) -> (f64, f64) {
        let t = kelvin * 1.4388 / 1.4380; // nominal to actual temperature, so 6500 K is D65
        let x = if t <= 7000.0 {
            -4.6070e9 / t.powi(3) + 2.9678e6 / t.powi(2) + 0.09911e3 / t + 0.244063
        } else {
            -2.0064e9 / t.powi(3) + 1.9018e6 / t.powi(2) + 0.24748e3 / t + 0.237040
        };
        (x, -3.0 * x * x + 2.87 * x - 0.275)
    }

    /// Kim et al.'s cubic fit to the Planckian locus.
    fn planck(t: f64) -> (f64, f64) {
        let x = if t <= 4000.0 {
            -0.2661239e9 / t.powi(3) - 0.2343589e6 / t.powi(2) + 0.8776956e3 / t + 0.179910
        } else {
            -3.0258469e9 / t.powi(3) + 2.1070379e6 / t.powi(2) + 0.2226347e3 / t + 0.240390
        };
        let y = if t <= 2222.0 {
            -1.1063814 * x.powi(3) - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
        } else if t <= 4000.0 {
            -0.9549476 * x.powi(3) - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
        } else {
            3.0817580 * x.powi(3) - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
        };
        (x, y)
    }

    /// Linear channel gains for a white of `kelvin`: the panel RGB that its EDID primaries need for
    /// that white (D65 at 6500 K gives 1, 1, 1), times the panel correction, largest scaled to 1.
    pub fn gains(kelvin: f64) -> Vec3 {
        let cols = EDID_PRIMARIES.map(xyz);
        let p: Mat3 = [0, 1, 2].map(|r| [cols[0][r], cols[1][r], cols[2][r]]);
        let s = solve(&p, xyz(white(6500.0)));
        let m: Mat3 = p.map(|row| [row[0] * s[0], row[1] * s[1], row[2] * s[2]]);
        let raw = solve(&m, xyz(white(kelvin)));
        let g = [0, 1, 2].map(|c| raw[c] * super::PANEL_CORRECTION[c]);
        let top = g[0].max(g[1]).max(g[2]);
        g.map(|v| v / top)
    }

    /// The sRGB colour (gamma-encoded, 0 to 1) of a white of `kelvin` beside D65, for swatches.
    pub fn swatch(kelvin: f64) -> Vec3 {
        let [x, y, z] = xyz(white(kelvin));
        let lin = [
            3.2406 * x - 1.5372 * y - 0.4986 * z,
            -0.9689 * x + 1.8758 * y + 0.0415 * z,
            0.0557 * x - 0.2040 * y + 1.0570 * z,
        ];
        let top = lin[0].max(lin[1]).max(lin[2]);
        lin.map(|v| {
            let v = (v / top).clamp(0.0, 1.0);
            if v <= 0.0031308 { 12.92 * v } else { 1.055 * v.powf(1.0 / 2.4) - 0.055 }
        })
    }
}

mod icc {
    /// The tag table: signature, offset, size.
    pub fn tags(data: &[u8]) -> Result<Vec<([u8; 4], usize, usize)>, String> {
        let word = |o: usize| {
            data.get(o..o + 4).map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]]) as usize).ok_or("ICC 文件不完整")
        };
        let n = word(128)?;
        (0..n)
            .map(|i| {
                let e = 132 + 12 * i;
                let sig = data.get(e..e + 4).ok_or("ICC 文件不完整")?;
                let (off, size) = (word(e + 4)?, word(e + 8)?);
                data.get(off..off + size).ok_or("ICC 标签越界")?;
                Ok(([sig[0], sig[1], sig[2], sig[3]], off, size))
            })
            .collect()
    }

    pub fn tag<'a>(data: &'a [u8], sig: &[u8; 4]) -> Option<&'a [u8]> {
        let (_, off, size) = tags(data).ok()?.into_iter().find(|t| &t.0 == sig)?;
        data.get(off..off + size)
    }

    fn s15(v: f64) -> [u8; 4] {
        ((v * 65536.0).round() as i32).to_be_bytes()
    }

    fn read_s15(b: &[u8]) -> f64 {
        i32::from_be_bytes([b[0], b[1], b[2], b[3]]) as f64 / 65536.0
    }

    pub fn read_xyz(data: &[u8], sig: &[u8; 4]) -> Option<[f64; 3]> {
        let t = tag(data, sig).filter(|t| t.len() >= 20 && &t[..4] == b"XYZ ")?;
        Some([0, 1, 2].map(|i| read_s15(&t[8 + 4 * i..])))
    }

    /// The formula vcgt: gamma, min and max for each channel.
    pub fn read_vcgt(data: &[u8]) -> Option<[[f64; 3]; 3]> {
        let t = tag(data, b"vcgt").filter(|t| t.len() >= 48 && t[8..12] == [0, 0, 0, 1])?;
        Some([0, 1, 2].map(|c| [0, 1, 2].map(|k| read_s15(&t[12 + 12 * c + 4 * k..]))))
    }

    /// `base` with its vcgt, names and (when given) colorants replaced; tags that shared data still do.
    pub fn build(
        base: &[u8],
        vcgt: &[[f64; 3]; 3],
        colorants: Option<[[f64; 3]; 3]>,
        ascii: &str,
        name: &str,
    ) -> Result<Vec<u8>, String> {
        let table = tags(base)?;
        let fresh = |sig: &[u8; 4]| -> Option<Vec<u8>> {
            let xyz = |c: [f64; 3]| [b"XYZ \0\0\0\0".as_slice(), &s15(c[0]), &s15(c[1]), &s15(c[2])].concat();
            match sig {
                b"vcgt" => {
                    let mut b = b"vcgt\0\0\0\0\0\0\0\x01".to_vec();
                    vcgt.iter().flatten().for_each(|v| b.extend(s15(*v)));
                    Some(b)
                }
                b"desc" => {
                    let mut b = b"desc\0\0\0\0".to_vec();
                    b.extend((ascii.len() as u32 + 1).to_be_bytes());
                    b.extend(ascii.bytes().chain([0]));
                    b.extend([0; 8 + 3 + 67]); // no Unicode or ScriptCode text
                    Some(b)
                }
                b"dscm" => {
                    let text: Vec<u8> = name.encode_utf16().flat_map(u16::to_be_bytes).collect();
                    let mut b = b"mluc\0\0\0\0\0\0\0\x01\0\0\0\x0cenUS".to_vec();
                    b.extend((text.len() as u32).to_be_bytes());
                    b.extend(28u32.to_be_bytes());
                    b.extend(text);
                    Some(b)
                }
                b"rXYZ" => colorants.map(|c| xyz(c[0])),
                b"gXYZ" => colorants.map(|c| xyz(c[1])),
                b"bXYZ" => colorants.map(|c| xyz(c[2])),
                _ => None,
            }
        };
        let start = 132 + 12 * table.len();
        let mut body: Vec<u8> = Vec::new();
        let mut place = |blob: &[u8]| {
            body.resize((start + body.len()).next_multiple_of(4) - start, 0);
            let at = (start + body.len()) as u32;
            body.extend_from_slice(blob);
            (at, blob.len() as u32)
        };
        let mut placed: Vec<((usize, usize), (u32, u32))> = Vec::new();
        let mut entries = Vec::new();
        for (sig, off, size) in &table {
            let spot = match fresh(sig) {
                Some(blob) => place(&blob),
                None => match placed.iter().find(|p| p.0 == (*off, *size)) {
                    Some(p) => p.1,
                    None => {
                        let spot = place(&base[*off..off + size]);
                        placed.push(((*off, *size), spot));
                        spot
                    }
                },
            };
            entries.push((*sig, spot));
        }
        body.resize((start + body.len()).next_multiple_of(4) - start, 0);
        let mut out = base[..128].to_vec();
        out[..4].copy_from_slice(&((start + body.len()) as u32).to_be_bytes());
        out[84..100].fill(0); // profile ID: none, as in a v2 profile
        out.extend((table.len() as u32).to_be_bytes());
        for (sig, (at, len)) in entries {
            out.extend(sig);
            out.extend(at.to_be_bytes());
            out.extend(len.to_be_bytes());
        }
        out.extend(body);
        Ok(out)
    }
}

/// ColorSync, CoreGraphics and CoreFoundation, declared by hand.
mod mac {
    use std::{
        ffi::c_void,
        os::unix::ffi::OsStrExt,
        path::{Path, PathBuf},
        ptr::null,
    };

    type Cf = *const c_void;
    #[repr(C)]
    struct Opaque([u8; 0]);

    #[link(name = "CoreFoundation", kind = "framework")]
    unsafe extern "C" {
        static kCFTypeDictionaryKeyCallBacks: Opaque;
        static kCFTypeDictionaryValueCallBacks: Opaque;
        fn CFDictionaryCreate(a: Cf, k: *const Cf, v: *const Cf, n: isize, kcb: *const Opaque, vcb: *const Opaque) -> Cf;
        fn CFDictionaryGetValue(d: Cf, key: Cf) -> Cf;
        fn CFDictionaryGetCount(d: Cf) -> isize;
        fn CFDictionaryGetKeysAndValues(d: Cf, keys: *mut Cf, values: *mut Cf);
        fn CFURLCreateFromFileSystemRepresentation(a: Cf, buf: *const u8, len: isize, dir: u8) -> Cf;
        fn CFURLGetFileSystemRepresentation(url: Cf, resolve: u8, buf: *mut u8, max: isize) -> u8;
        fn CFGetTypeID(cf: Cf) -> usize;
        fn CFURLGetTypeID() -> usize;
        fn CFDictionaryGetTypeID() -> usize;
        fn CFStringGetTypeID() -> usize;
        fn CFRelease(cf: Cf);
    }

    #[link(name = "ColorSync", kind = "framework")]
    unsafe extern "C" {
        static kColorSyncDisplayDeviceClass: Cf;
        static kColorSyncDeviceDefaultProfileID: Cf;
        static kColorSyncCustomProfiles: Cf;
        static kColorSyncFactoryProfiles: Cf;
        static kColorSyncDeviceProfileURL: Cf;
        fn ColorSyncDeviceSetCustomProfiles(class: Cf, device: Cf, info: Cf) -> bool;
        fn ColorSyncDeviceCopyDeviceInfo(class: Cf, device: Cf) -> Cf;
        fn CGDisplayCreateUUIDFromDisplayID(display: u32) -> Cf;
    }

    #[link(name = "CoreGraphics", kind = "framework")]
    unsafe extern "C" {
        fn CGGetOnlineDisplayList(max: u32, displays: *mut u32, count: *mut u32) -> i32;
        fn CGDisplayVendorNumber(display: u32) -> u32;
        fn CGDisplayModelNumber(display: u32) -> u32;
        fn CGGetDisplayTransferByTable(d: u32, cap: u32, r: *mut f32, g: *mut f32, b: *mut f32, n: *mut u32) -> i32;
        #[rustfmt::skip]
        fn CGSetDisplayTransferByFormula(d: u32, r0: f32, r1: f32, rg: f32, g0: f32, g1: f32, gg: f32, b0: f32, b1: f32, bg: f32) -> i32;
    }

    /// The PU15-PRE's display ID, if it is online.
    pub fn display() -> Option<u32> {
        let (mut ids, mut n) = ([0u32; 16], 0u32);
        unsafe { CGGetOnlineDisplayList(16, ids.as_mut_ptr(), &mut n) };
        ids[..n as usize]
            .iter()
            .copied()
            .find(|&d| unsafe { CGDisplayVendorNumber(d) == 0x25E3 && CGDisplayModelNumber(d) == 0x1501 })
    }

    /// The display's custom and factory profiles.
    pub fn profiles(display: u32) -> (Option<PathBuf>, Option<PathBuf>) {
        unsafe {
            let uuid = CGDisplayCreateUUIDFromDisplayID(display);
            if uuid.is_null() {
                return (None, None);
            }
            let info = ColorSyncDeviceCopyDeviceInfo(kColorSyncDisplayDeviceClass, uuid);
            CFRelease(uuid);
            if info.is_null() {
                return (None, None);
            }
            let custom = default_profile(CFDictionaryGetValue(info, kColorSyncCustomProfiles));
            let factory = default_profile(CFDictionaryGetValue(info, kColorSyncFactoryProfiles));
            CFRelease(info);
            (custom, factory)
        }
    }

    /// A profiles dictionary maps profile IDs to URLs, or to dictionaries holding one; the entry
    /// under DeviceDefaultProfileID names the default, or is it.
    unsafe fn default_profile(dict: Cf) -> Option<PathBuf> {
        unsafe {
            if dict.is_null() || CFGetTypeID(dict) != CFDictionaryGetTypeID() {
                return None;
            }
            let mut pick = CFDictionaryGetValue(dict, kColorSyncDeviceDefaultProfileID);
            if !pick.is_null() && CFGetTypeID(pick) == CFStringGetTypeID() {
                pick = CFDictionaryGetValue(dict, pick);
            }
            if let Some(path) = path_of(pick) {
                return Some(path);
            }
            let n = CFDictionaryGetCount(dict) as usize;
            let (mut keys, mut values) = (vec![null(); n], vec![null(); n]);
            CFDictionaryGetKeysAndValues(dict, keys.as_mut_ptr(), values.as_mut_ptr());
            values.into_iter().find_map(|v| path_of(v))
        }
    }

    unsafe fn path_of(value: Cf) -> Option<PathBuf> {
        unsafe {
            if value.is_null() {
                return None;
            }
            let mut url = value;
            if CFGetTypeID(url) == CFDictionaryGetTypeID() {
                url = CFDictionaryGetValue(url, kColorSyncDeviceProfileURL);
            }
            if url.is_null() || CFGetTypeID(url) != CFURLGetTypeID() {
                return None;
            }
            let mut buf = [0u8; 1024];
            if CFURLGetFileSystemRepresentation(url, 1, buf.as_mut_ptr(), buf.len() as isize) == 0 {
                return None;
            }
            let len = buf.iter().position(|&b| b == 0)?;
            Some(PathBuf::from(std::ffi::OsStr::from_bytes(&buf[..len])))
        }
    }

    pub fn assign(display: u32, profile: &Path) -> Result<(), String> {
        let bytes = profile.as_os_str().as_bytes();
        unsafe {
            let url = CFURLCreateFromFileSystemRepresentation(null(), bytes.as_ptr(), bytes.len() as isize, 0);
            let uuid = CGDisplayCreateUUIDFromDisplayID(display);
            if url.is_null() || uuid.is_null() {
                return Err("拿不到显示器的 ColorSync 设备".into());
            }
            let (keys, values) = ([kColorSyncDeviceDefaultProfileID], [url]);
            let info = CFDictionaryCreate(
                null(),
                keys.as_ptr(),
                values.as_ptr(),
                1,
                &raw const kCFTypeDictionaryKeyCallBacks,
                &raw const kCFTypeDictionaryValueCallBacks,
            );
            let ok = ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass, uuid, info);
            CFRelease(info);
            CFRelease(uuid);
            CFRelease(url);
            if ok { Ok(()) } else { Err("ColorSync 没有接受这个配置文件".into()) }
        }
    }

    /// The display's current gamma table, one curve per channel.
    pub fn gamma_table(display: u32) -> Option<[Vec<f32>; 3]> {
        let (mut r, mut g, mut b, mut n) = (vec![0f32; 1024], vec![0f32; 1024], vec![0f32; 1024], 0u32);
        let err = unsafe {
            CGGetDisplayTransferByTable(display, 1024, r.as_mut_ptr(), g.as_mut_ptr(), b.as_mut_ptr(), &mut n)
        };
        if err != 0 || n == 0 {
            return None;
        }
        for c in [&mut r, &mut g, &mut b] {
            c.truncate(n as usize);
        }
        Some([r, g, b])
    }

    /// Shows a curve at once without touching the profile; macOS restores the profile's own
    /// curve when this process exits.
    pub fn preview(display: u32, vcgt: &[[f64; 3]; 3]) {
        let [r, g, b] = vcgt.map(|[gamma, min, max]| [min as f32, max as f32, gamma as f32]);
        unsafe { CGSetDisplayTransferByFormula(display, r[0], r[1], r[2], g[0], g[1], g[2], b[0], b[1], b[2]) };
    }
}

const BASE_PROFILE: &str = "/Library/ColorSync/Profiles/Displays/PU15-PRE-DB36DCA8-111C-4D25-BFB2-9E49A104EC88.icc";
const BETTERDISPLAY: &str = "/Applications/Nix Apps/BetterDisplay.app/Contents/MacOS/BetterDisplay";
/// Every profile made here starts with this; the older warm.py ones did too.
const PREFIX: &str = "PU15-PRE-";

fn profiles_dir() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join("Library/ColorSync/Profiles")
}

/// The calibration curve: gamma, min and max for R, G and B.
fn vcgt(look: &Look) -> [[f64; 3]; 3] {
    let gains = color::gains(look.kelvin as f64);
    let gamma = SCHEMES[look.scheme].tone / color::NATIVE_GAMMA;
    let scale = look.percent as f64 / 100.0;
    gains.map(|g| [gamma, 0.0, scale * g.powf(1.0 / color::NATIVE_GAMMA)])
}

fn short(v: f64) -> String {
    let s = format!("{v:.3}");
    s.trim_end_matches('0').trim_end_matches('.').to_string()
}

/// The profile's bytes and its file name. The name ends in a hash of the bytes, so a changed
/// profile never reuses a name that ColorSync may have cached.
fn make_profile(base: &[u8], target: &Target) -> Result<(Vec<u8>, String), String> {
    let (curve, colorants, ascii, name, stem) = match target {
        Target::Look(look) => {
            let s = &SCHEMES[look.scheme];
            let colorants = (s.vivid > 0.0)
                .then(|| {
                    let edid = [b"rXYZ", b"gXYZ", b"bXYZ"].map(|sig| icc::read_xyz(base, sig));
                    let [Some(r), Some(g), Some(b)] = edid else { return None };
                    let mix = |e: [f64; 3], s3: [f64; 3]| [0, 1, 2].map(|i| e[i] + s.vivid * (s3[i] - e[i]));
                    let srgb = color::SRGB_COLORANTS;
                    Some([mix(r, srgb[0]), mix(g, srgb[1]), mix(b, srgb[2])])
                })
                .flatten();
            let (k, p) = (look.kelvin, look.percent);
            (
                vcgt(look),
                colorants,
                format!("PU15-PRE {} {k}K {p}%", s.id),
                format!("PU15-PRE {} {k}K {p}%", s.name),
                format!("{PREFIX}{}-{k}K-{p}", s.id),
            )
        }
        Target::Rgb(gains) => {
            let label = format!("PU15-PRE rgb {} {} {}", short(gains[0]), short(gains[1]), short(gains[2]));
            let curve = gains.map(|g| [1.0, 0.0, g.powf(1.0 / color::NATIVE_GAMMA)]);
            (curve, None, label.clone(), label, format!("{PREFIX}rgb"))
        }
        Target::File(_) => unreachable!("a profile file is assigned as it is"),
    };
    let bytes = icc::build(base, &curve, colorants, &ascii, &name)?;
    let hash = bytes.iter().fold(0xcbf2_9ce4_8422_2325u64, |h, &b| (h ^ b as u64).wrapping_mul(0x100_0000_01b3));
    Ok((bytes, format!("{stem}-{:08x}.icc", hash as u32)))
}

struct Applied {
    path: PathBuf,
    better_display: Result<(), String>,
}

/// Makes and assigns the profile, tells BetterDisplay, and removes the profiles it replaced.
fn apply(target: &Target) -> Result<Applied, String> {
    let display = mac::display().ok_or("PU15-PRE 没有连接")?;
    let path = match target {
        Target::File(path) => path.clone(),
        _ => {
            let base_path = mac::profiles(display).1.unwrap_or_else(|| BASE_PROFILE.into());
            let base = fs::read(&base_path).map_err(|e| format!("读不了 {}：{e}", base_path.display()))?;
            let (bytes, name) = make_profile(&base, target)?;
            let dir = profiles_dir();
            let path = dir.join(&name);
            if !path.exists() {
                let tmp = dir.join(format!(".{name}.tmp"));
                fs::create_dir_all(&dir)
                    .and_then(|_| fs::write(&tmp, &bytes))
                    .and_then(|_| fs::rename(&tmp, &path))
                    .map_err(|e| format!("写不了配置文件：{e}"))?;
            }
            path
        }
    };
    mac::assign(display, &path)?;
    // BetterDisplay re-applies its stored file on reconnect, so the old file stays until it is updated.
    let better_display = better_display(&["set", "-name=PU15-PRE", &format!("-colorProfileURL={}", file_url(&path))])
        .map(|_| ());
    if better_display.is_ok() {
        for entry in fs::read_dir(profiles_dir()).into_iter().flatten().flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with(PREFIX) && name.ends_with(".icc") && entry.path() != path {
                let _ = fs::remove_file(entry.path());
            }
        }
    }
    Ok(Applied { path, better_display })
}

/// The latest request from the window wins: an older one still waiting for the lock is dropped.
static APPLY_LOCK: Mutex<()> = Mutex::new(());
static LATEST: AtomicU64 = AtomicU64::new(0);

fn apply_latest(seq: u64, target: Target) -> Option<Result<Applied, String>> {
    let _guard = APPLY_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    (LATEST.load(Ordering::SeqCst) == seq).then(|| apply(&target))
}

fn file_url(path: &Path) -> String {
    let mut url = String::from("file://");
    for b in path.to_string_lossy().bytes() {
        if b.is_ascii_alphanumeric() || b"/-._~".contains(&b) {
            url.push(b as char);
        } else {
            url.push_str(&format!("%{b:02X}"));
        }
    }
    url
}

fn better_display(args: &[&str]) -> Result<String, String> {
    let mut child = Command::new(BETTERDISPLAY)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("BetterDisplay 打不开：{e}"))?;
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let mut out = String::new();
                if let Some(mut pipe) = child.stdout.take() {
                    let _ = std::io::Read::read_to_string(&mut pipe, &mut out);
                }
                return if status.success() { Ok(out.trim().to_string()) } else { Err("BetterDisplay 没有更新".into()) };
            }
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(30)),
            _ => {
                let _ = child.kill();
                return Err("BetterDisplay 没有响应".into());
            }
        }
    }
}

/// Which scheme a profile is: from the name this script gives it, or else by matching the curve
/// of an older profile against each scheme's.
fn identify(path: &Path) -> Option<Look> {
    let stem = path.file_stem()?.to_str()?.strip_prefix(PREFIX)?;
    if let [id, k, p, _hash] = stem.split('-').collect::<Vec<_>>()[..] {
        let scheme = SCHEMES.iter().position(|s| s.id == id)?;
        return Some(Look { scheme, kelvin: k.strip_suffix('K')?.parse().ok()?, percent: p.parse().ok()? });
    }
    let curve = icc::read_vcgt(&fs::read(path).ok()?)?;
    (0..SCHEMES.len()).map(Look::of).find(|look| {
        let want = vcgt(look);
        (0..3).all(|c| (0..3).all(|k| (want[c][k] - curve[c][k]).abs() < 2e-4))
    })
}

enum Current {
    Offline,
    Factory,
    Look(Look),
    Other(PathBuf),
}

fn current() -> Current {
    let Some(display) = mac::display() else { return Current::Offline };
    match mac::profiles(display).0 {
        None => Current::Factory,
        Some(path) => identify(&path).map_or(Current::Other(path), Current::Look),
    }
}

mod cli {
    use super::*;

    pub const USAGE: &str = "innocn-color                  open the picker
innocn-color list             the schemes and the gains each gives
innocn-color status           the active profile and the display's gamma table
innocn-color apply <scheme> [K] [brightness%]
innocn-color apply rgb R G B  raw linear gains, without the panel correction
innocn-color apply <file.icc>";

    pub fn list() -> i32 {
        println!("id        white  tone  vivid  bright  gains R G B          vcgt max R G B       name");
        for (i, s) in SCHEMES.iter().enumerate() {
            let g = color::gains(s.white as f64);
            let v = vcgt(&Look::of(i));
            println!(
                "{:<9} {:>4}K  {:<4}  {:<5}  {:>5}%  {:.3} {:.3} {:.3}  {:.3} {:.3} {:.3}  {}",
                s.id, s.white, s.tone, s.vivid, s.brightness, g[0], g[1], g[2], v[0][2], v[1][2], v[2][2], s.name
            );
        }
        0
    }

    pub fn status() -> i32 {
        let Some(display) = mac::display() else {
            println!("PU15-PRE 没有连接");
            return 1;
        };
        let (custom, factory) = mac::profiles(display);
        match &custom {
            Some(path) => match identify(path) {
                Some(look) => println!("{}", look.describe()),
                None => println!("其他配置文件"),
            },
            None => println!("出厂配置文件"),
        }
        let show = |p: &Option<PathBuf>| p.as_ref().map_or("-".into(), |p| p.display().to_string());
        println!("profile        {}", show(&custom));
        println!("factory        {}", show(&factory));
        match better_display(&["get", "-name=PU15-PRE", "-colorProfileURL"]) {
            Ok(url) => println!("BetterDisplay  {url}"),
            Err(e) => println!("BetterDisplay  {e}"),
        }
        if let Some([r, g, b]) = mac::gamma_table(display) {
            let (n, mid) = (r.len(), r.len() / 2);
            println!(
                "gamma table ({n}): mid R {:.4} G {:.4} B {:.4}   top R {:.4} G {:.4} B {:.4}",
                r[mid], g[mid], b[mid], r[n - 1], g[n - 1], b[n - 1]
            );
        }
        0
    }

    pub fn apply(args: &[String]) -> i32 {
        let target = match parse(args) {
            Ok(target) => target,
            Err(e) => {
                eprintln!("{e}\n\n{USAGE}");
                return 2;
            }
        };
        if let Target::Look(look) = &target {
            let v = vcgt(look);
            println!("{}: vcgt gamma {:.4}, max R {:.4} G {:.4} B {:.4}", look.describe(), v[0][0], v[0][2], v[1][2], v[2][2]);
        }
        match super::apply(&target) {
            Ok(applied) => {
                println!("assigned       {}", applied.path.display());
                if let Err(e) = applied.better_display {
                    println!("{e}");
                }
                std::thread::sleep(Duration::from_secs(1)); // ColorSync loads the curve asynchronously
                status()
            }
            Err(e) => {
                eprintln!("{e}");
                1
            }
        }
    }

    fn parse(args: &[String]) -> Result<Target, String> {
        let num = |s: &String| s.trim_end_matches(['K', 'k', '%']).parse::<f64>().map_err(|_| format!("不是数字：{s}"));
        match args {
            [rgb, r, g, b] if rgb == "rgb" => Ok(Target::Rgb([num(r)?, num(g)?, num(b)?])),
            [file] if file.ends_with(".icc") => Ok(Target::File(fs::canonicalize(file).map_err(|e| format!("{file}：{e}"))?)),
            [scheme, rest @ ..] if rest.len() <= 2 => {
                let i = SCHEMES
                    .iter()
                    .position(|s| s.id == scheme || s.name == scheme)
                    .ok_or_else(|| format!("没有这个方案：{scheme}"))?;
                let mut look = Look::of(i);
                if let Some(k) = rest.first() {
                    look.kelvin = (num(k)?.round() as u32).clamp(1700, 12000);
                }
                if let Some(p) = rest.get(1) {
                    look.percent = (num(p)?.round() as u32).clamp(10, 100);
                }
                Ok(Target::Look(look))
            }
            _ => Err("apply 后面要写方案名".into()),
        }
    }
}

mod ui {
    use super::*;
    use gpui::{
        App, ClickEvent, Context, Div, Entity, FocusHandle, FontFeatures, FontWeight, Hsla, KeyBinding, KeyDownEvent,
        Menu, MenuItem, Pixels, SharedString, Size, Stateful, Subscription, TitlebarOptions, Window, WindowBounds,
        WindowOptions, div, point, prelude::*, px, rgb, rgba, size,
    };
    use gpui_component::{
        Icon, IconName, Root, Theme,
        slider::{Slider, SliderEvent, SliderState},
    };

    gpui::actions!(innocn_color, [Quit, CloseWindow]);

    const TITLE_H: f32 = 38.;
    const ROW_H: f32 = 46.;
    const SLIDER_H: f32 = 36.;
    const CONTROL_H: f32 = 28.;
    const FOOTER_H: f32 = 48.;
    const PAD: f32 = 16.;

    fn window_size() -> Size<Pixels> {
        size(px(400.), px(TITLE_H + ROW_H * SCHEMES.len() as f32 + SLIDER_H * 2. + 16. + FOOTER_H))
    }

    /// Warm paper by day, a warm dark at night; the window follows the system appearance.
    struct Palette {
        bg: u32,
        rule: u32,
        hover: u32,
        selected: u32,
        fg: u32,
        muted: u32,
        accent: u32,
        thumb: u32,
        edge: u32,
        press: u32,
        swatch_edge: u32,
    }

    const PAPER: Palette = Palette {
        bg: 0xF7F2E8,
        rule: 0xE5DCCC,
        hover: 0xF1EADD,
        selected: 0xEDE3D1,
        fg: 0x2E2822,
        muted: 0x857A6B,
        accent: 0xB0602F,
        thumb: 0xFFFCF6,
        edge: 0xD9CEBB,
        press: 0xE8DECC,
        swatch_edge: 0x2E28222E,
    };

    const NIGHT: Palette = Palette {
        bg: 0x1F1C18,
        rule: 0x35302A,
        hover: 0x26231E,
        selected: 0x2D2923,
        fg: 0xEBE3D5,
        muted: 0x9E927F,
        accent: 0xDC9259,
        thumb: 0xF4EDE2,
        edge: 0x433D35,
        press: 0x36312A,
        swatch_edge: 0xEBE3D533,
    };

    fn c(hex: u32) -> Hsla {
        rgb(hex).into()
    }

    fn palette(cx: &App) -> &'static Palette {
        if Theme::global(cx).is_dark() { &NIGHT } else { &PAPER }
    }

    fn set_theme(dark: bool, cx: &mut App) {
        Theme::change(if dark { gpui_component::ThemeMode::Dark } else { gpui_component::ThemeMode::Light }, None, cx);
        let accent = c(palette(cx).accent);
        Theme::global_mut(cx).ring = accent;
        Theme::sync_base(cx);
    }

    fn now_showing(look: &Look) -> String {
        let name = SCHEMES[look.scheme].name;
        if *look == Look::of(look.scheme) { format!("当前：{name}") } else { format!("当前：{name}（已微调）") }
    }

    fn is_dark(window: &Window) -> bool {
        matches!(window.appearance(), gpui::WindowAppearance::Dark | gpui::WindowAppearance::VibrantDark)
    }

    pub struct Picker {
        look: Look,
        applied: Option<usize>,
        note: SharedString,
        display: Option<u32>,
        kelvin: Entity<SliderState>,
        percent: Entity<SliderState>,
        focus: FocusHandle,
        slide_generation: u64,
        _subscriptions: Vec<Subscription>,
    }

    impl Picker {
        pub fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
            let (look, applied, note) = match current() {
                Current::Look(look) => (look, Some(look.scheme), now_showing(&look)),
                Current::Factory => (Look::of(0), None, "当前是出厂配置文件".into()),
                Current::Other(path) => (
                    Look::of(0),
                    None,
                    format!("当前是别的配置文件：{}", path.file_name().unwrap_or_default().to_string_lossy()),
                ),
                Current::Offline => (Look::of(0), None, "PU15-PRE 没有连接".into()),
            };
            let kelvin = cx.new(|_| {
                SliderState::new()
                    .max(KELVIN_RANGE.1 as f32) // before min: each call clamps to the other bound
                    .min(KELVIN_RANGE.0 as f32)
                    .step(100.)
                    .default_value(look.kelvin as f32)
            });
            let percent = cx.new(|_| {
                SliderState::new()
                    .max(PERCENT_RANGE.1 as f32)
                    .min(PERCENT_RANGE.0 as f32)
                    .step(5.)
                    .default_value(look.percent as f32)
            });
            let focus = cx.focus_handle();
            window.focus(&focus, cx);
            let _subscriptions = vec![
                cx.subscribe_in(&kelvin, window, |this, _, event: &SliderEvent, _, cx| {
                    let (SliderEvent::Change(v) | SliderEvent::Release(v)) = event;
                    this.look.kelvin = v.end().round() as u32;
                    this.slid(matches!(event, SliderEvent::Release(_)), cx);
                }),
                cx.subscribe_in(&percent, window, |this, _, event: &SliderEvent, _, cx| {
                    let (SliderEvent::Change(v) | SliderEvent::Release(v)) = event;
                    this.look.percent = v.end().round() as u32;
                    this.slid(matches!(event, SliderEvent::Release(_)), cx);
                }),
                cx.observe_window_appearance(window, |_, window, cx| {
                    set_theme(is_dark(window), cx);
                    cx.notify();
                }),
            ];
            Self {
                look,
                applied,
                note: note.into(),
                display: mac::display(),
                kelvin,
                percent,
                focus,
                slide_generation: 0,
                _subscriptions,
            }
        }

        fn pick(&mut self, scheme: usize, window: &mut Window, cx: &mut Context<Self>) {
            self.look = Look::of(scheme);
            self.applied = Some(scheme);
            let (k, p) = (self.look.kelvin as f32, self.look.percent as f32);
            self.kelvin.update(cx, |s, cx| s.set_value(k, window, cx));
            self.percent.update(cx, |s, cx| s.set_value(p, window, cx));
            self.commit(cx);
        }

        /// While a slider moves, the curve is shown directly; the profile follows when it is
        /// released, or after a short pause.
        fn slid(&mut self, released: bool, cx: &mut Context<Self>) {
            self.applied.get_or_insert(self.look.scheme);
            self.slide_generation += 1;
            if released {
                self.commit(cx);
            } else {
                if let Some(display) = self.display {
                    mac::preview(display, &vcgt(&self.look));
                }
                let generation = self.slide_generation;
                cx.spawn(async move |this, cx| {
                    cx.background_executor().timer(Duration::from_millis(600)).await;
                    this.update(cx, |this, cx| {
                        if this.slide_generation == generation {
                            this.commit(cx);
                        }
                    })
                    .ok();
                })
                .detach();
            }
            cx.notify();
        }

        fn commit(&mut self, cx: &mut Context<Self>) {
            self.slide_generation += 1;
            let look = self.look;
            let seq = LATEST.fetch_add(1, Ordering::SeqCst) + 1;
            let job = cx.background_spawn(async move { apply_latest(seq, Target::Look(look)) });
            cx.spawn(async move |this, cx| {
                let Some(result) = job.await else { return };
                this.update(cx, |this, cx| {
                    this.note = match result {
                        Ok(applied) => match applied.better_display {
                            Ok(()) => now_showing(&look),
                            Err(e) => format!("{}，但 {e}", now_showing(&look)),
                        },
                        Err(e) => format!("没能切换：{e}"),
                    }
                    .into();
                    cx.notify();
                })
                .ok();
            })
            .detach();
        }

        fn key(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
            let digit = event.keystroke.key.parse::<usize>().ok();
            if let Some(n) = digit.filter(|n| (1..=SCHEMES.len()).contains(n)) {
                if !event.keystroke.modifiers.modified() {
                    self.pick(n - 1, window, cx);
                }
            }
        }

        fn row(&self, i: usize, p: &'static Palette, cx: &mut Context<Self>) -> Stateful<Div> {
            let scheme = &SCHEMES[i];
            let on = self.applied == Some(i);
            let look = if on { self.look } else { Look::of(i) };
            let [r, g, b] = color::swatch(look.kelvin as f64);
            let swatch = gpui::Rgba { r: r as f32, g: g as f32, b: b as f32, a: 1. };
            div()
                .id(("scheme", i))
                .flex_none()
                .h(px(ROW_H))
                .px(px(PAD))
                .flex()
                .items_center()
                .gap(px(12.))
                .border_b_1()
                .border_color(c(p.rule))
                .when(on, |row| row.bg(c(p.selected)))
                .when(!on, |row| row.hover(|style| style.bg(c(p.hover))))
                .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| this.pick(i, window, cx)))
                .child(div().flex_none().size(px(24.)).rounded(px(5.)).bg(swatch).border_1().border_color(rgba(p.swatch_edge)))
                .child(
                    div()
                        .flex_1()
                        .flex()
                        .flex_col()
                        .gap(px(1.))
                        .child(div().text_size(px(13.)).line_height(px(18.)).font_weight(FontWeight::MEDIUM).child(scheme.name))
                        .child(
                            div()
                                .text_size(px(12.))
                                .line_height(px(16.))
                                .text_color(c(p.muted))
                                .child(format!("{}K · {}", look.kelvin, scheme.purpose)),
                        ),
                )
                .when(on, |row| row.child(Icon::new(IconName::Check).size(px(16.)).text_color(c(p.accent))))
        }

        fn slider(&self, label: &'static str, state: &Entity<SliderState>, value: String, p: &Palette) -> Div {
            div()
                .h(px(SLIDER_H))
                .flex()
                .items_center()
                .gap(px(12.))
                .child(div().flex_none().w(px(28.)).text_size(px(13.)).child(label))
                .child(Slider::new(state).flex_1().bg(c(p.accent)).text_color(c(p.thumb)))
                .child(
                    div()
                        .flex_none()
                        .w(px(48.))
                        .text_right()
                        .text_size(px(12.))
                        .text_color(c(p.muted))
                        .font_features(FontFeatures(std::sync::Arc::new(vec![("tnum".into(), 1)])))
                        .child(value),
                )
        }
    }

    impl Render for Picker {
        fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
            let p = palette(cx);
            let standard = self.applied == Some(0) && self.look == Look::of(0);
            div()
                .track_focus(&self.focus)
                .on_key_down(cx.listener(Self::key))
                .on_action(cx.listener(|_, _: &CloseWindow, window, _| window.remove_window()))
                .size_full()
                .flex()
                .flex_col()
                .bg(c(p.bg))
                .text_color(c(p.fg))
                .text_size(px(13.))
                .child(
                    div()
                        .flex_none()
                        .h(px(TITLE_H))
                        .flex()
                        .items_center()
                        .justify_center()
                        .border_b_1()
                        .border_color(c(p.rule))
                        .text_size(px(13.))
                        .font_weight(FontWeight::SEMIBOLD)
                        .child("INNOCN 色彩模式"),
                )
                .children((0..SCHEMES.len()).map(|i| self.row(i, p, cx)))
                .child(
                    div()
                        .flex_none()
                        .px(px(PAD))
                        .py(px(8.))
                        .border_b_1()
                        .border_color(c(p.rule))
                        .child(self.slider("色温", &self.kelvin, format!("{}K", self.look.kelvin), p))
                        .child(self.slider("亮度", &self.percent, format!("{}%", self.look.percent), p)),
                )
                .child(
                    div()
                        .flex_1()
                        .px(px(PAD))
                        .flex()
                        .items_center()
                        .justify_between()
                        .gap(px(12.))
                        .child(div().flex_1().min_w_0().truncate().text_size(px(12.)).text_color(c(p.muted)).child(self.note.clone()))
                        .child(
                            div()
                                .id("standard")
                                .flex_none()
                                .h(px(CONTROL_H))
                                .px(px(12.))
                                .flex()
                                .items_center()
                                .rounded(px(6.))
                                .border_1()
                                .border_color(c(p.edge))
                                .when(standard, |button| button.text_color(c(p.muted)))
                                .when(!standard, |button| {
                                    button
                                        .hover(|style| style.bg(c(p.hover)))
                                        .active(|style| style.bg(c(p.press)))
                                        .on_click(cx.listener(|this, _: &ClickEvent, window, cx| this.pick(0, window, cx)))
                                })
                                .child("恢复标准"),
                        ),
                )
        }
    }

    pub fn run() {
        gpui_platform::application().with_assets(gpui_kit_assets::Assets).run(|cx: &mut App| {
            gpui_component::init(cx);
            cx.bind_keys([KeyBinding::new("cmd-q", Quit, None), KeyBinding::new("cmd-w", CloseWindow, None)]);
            cx.on_action(|_: &Quit, cx| cx.quit());
            cx.set_menus([Menu::new("INNOCN Color").items([MenuItem::action("退出 INNOCN Color", Quit)])]);
            cx.on_window_closed(|cx, _| cx.quit()).detach();
            let options = WindowOptions {
                window_bounds: Some(WindowBounds::centered(window_size(), cx)),
                titlebar: Some(TitlebarOptions {
                    title: Some("INNOCN 色彩模式".into()),
                    appears_transparent: true,
                    traffic_light_position: Some(point(px(13.), px(12.))),
                }),
                is_resizable: false,
                ..Default::default()
            };
            cx.open_window(options, |window, cx| {
                set_theme(is_dark(window), cx);
                let picker = cx.new(|cx| Picker::new(window, cx));
                cx.new(|cx| Root::new(picker, window, cx))
            })
            .expect("could not open the window");
            cx.activate(true);
        });
    }

    #[cfg(feature = "shot")]
    pub fn shot(args: &[String]) -> i32 {
        let out = args.first().cloned().unwrap_or_else(|| "shot.png".into());
        let dark = args.get(1).is_some_and(|a| a == "dark");
        let mark = args.get(2).and_then(|id| SCHEMES.iter().position(|s| s.id == id));
        let text = gpui_platform::current_platform(true).text_system();
        let mut cx = gpui::HeadlessAppContext::with_platform(
            text,
            std::sync::Arc::new(gpui_kit_assets::Assets),
            gpui_platform::current_headless_renderer,
        );
        cx.update(gpui_component::init);
        let window = cx
            .open_window(window_size(), |window, cx| {
                let picker = cx.new(|cx| {
                    let mut picker = Picker::new(window, cx);
                    if let Some(i) = mark {
                        picker.look = Look::of(i);
                        picker.applied = Some(i);
                        let (k, p) = (picker.look.kelvin as f32, picker.look.percent as f32);
                        picker.kelvin.update(cx, |s, cx| s.set_value(k, window, cx));
                        picker.percent.update(cx, |s, cx| s.set_value(p, window, cx));
                    }
                    picker
                });
                cx.new(|cx| Root::new(picker, window, cx))
            })
            .expect("could not open the window");
        // after opening, which syncs the theme to the (light) test window once
        cx.update(|cx| set_theme(dark, cx));
        for _ in 0..3 {
            cx.update_window(window.into(), |_, window, cx| window.draw(cx).clear(cx)).ok();
            cx.run_until_parked();
        }
        match cx.capture_screenshot(window.into()).map_err(|e| e.to_string()).and_then(|image| image.save(&out).map_err(|e| e.to_string())) {
            Ok(()) => 0,
            Err(e) => {
                eprintln!("{e}");
                1
            }
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).filter(|a| !a.starts_with("-psn_")).collect();
    let code = match args.first().map(String::as_str) {
        None => {
            ui::run();
            0
        }
        Some("list") => cli::list(),
        Some("status") => cli::status(),
        Some("apply") => cli::apply(&args[1..]),
        Some("binary-path") => {
            println!("{}", std::env::current_exe().map(|p| p.display().to_string()).unwrap_or_default());
            0
        }
        #[cfg(feature = "shot")]
        Some("shot") => ui::shot(&args[1..]),
        Some(_) => {
            eprintln!("{}", cli::USAGE);
            2
        }
    };
    std::process::exit(code);
}
