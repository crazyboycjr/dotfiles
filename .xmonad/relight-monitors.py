#!/usr/bin/env python3
"""Relight a monitor when it comes back.

When a DisplayPort monitor reconnects (powered back on, or the KVM script
switches it back), the NVIDIA X driver notices but does not set its mode again,
so the screen stays black until a VT switch forces a modeset. This watches the
outputs and, a few seconds after one reconnects, turns it off and on again with
the mode and position it had.

    relight-monitors.py          watch (started from .xinitrc)
    relight-monitors.py --now    relight every connected output once
"""
import select
import subprocess
import sys
import time

from Xlib import display
from Xlib.ext import randr

SETTLE = [1.0, 2.0, 3.0]
ROTATIONS = {1: "normal", 2: "left", 4: "inverted", 8: "right"}


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def snapshot(d, root):
    res = root.xrandr_get_screen_resources_current()
    primary = root.xrandr_get_output_primary().output
    outputs = {}
    for out in res.outputs:
        info = d.xrandr_get_output_info(out, res.config_timestamp)
        layout = None
        if info.crtc:
            crtc = d.xrandr_get_crtc_info(info.crtc, res.config_timestamp)
            if crtc.mode:
                layout = (crtc.mode, crtc.x, crtc.y, ROTATIONS.get(crtc.rotation & 0xF, "normal"), out == primary)
        outputs[info.name] = (info.connection == randr.Connected, layout)
    return outputs


def relight(name, layout):
    mode, x, y, rotation, primary = layout
    on = ["xrandr", "--output", name, "--mode", hex(mode), "--pos", f"{x}x{y}", "--rotate", rotation]
    if primary:
        on.append("--primary")
    log(f"relight {name}: {' '.join(on[3:])}")
    subprocess.run(["xrandr", "--output", name, "--off"], check=False)
    return subprocess.run(on, check=False).returncode == 0


def configure(name):
    detected = subprocess.run(["autorandr", "--detected"], capture_output=True, text=True).stdout.split()
    if detected:
        log(f"{name} connected without a mode, applying autorandr profile {detected[0]}")
        return subprocess.run(["autorandr", "--change"], check=False).returncode == 0
    log(f"{name} connected without a mode, cloning the primary at 0x0")
    return subprocess.run(["xrandr", "--output", name, "--auto", "--pos", "0x0"], check=False).returncode == 0


def main():
    d = display.Display()
    root = d.screen().root
    if "--now" in sys.argv:
        for name, (connected, layout) in snapshot(d, root).items():
            if connected and layout:
                relight(name, layout)
        return
    root.xrandr_select_input(randr.RROutputChangeNotifyMask | randr.RRCrtcChangeNotifyMask | randr.RRScreenChangeNotifyMask)
    state = snapshot(d, root)
    remembered = {name: layout for name, (_, layout) in state.items() if layout}
    due = {}
    log("watching " + ", ".join(f"{n}{'' if c else ' (off)'}" for n, (c, _) in state.items() if c or n in remembered))
    while True:
        timeout = max(0.0, min(t for t, _ in due.values()) - time.monotonic()) if due else None
        if not d.pending_events():
            select.select([d.fileno()], [], [], timeout)
        while d.pending_events():
            d.next_event()
        now = snapshot(d, root)
        for name, (connected, layout) in now.items():
            was_connected = state.get(name, (False, None))[0]
            if connected and not was_connected:
                log(f"{name} reconnected")
                due[name] = (time.monotonic() + SETTLE[0], 0)
            elif not connected and was_connected:
                log(f"{name} disconnected")
                due.pop(name, None)
            if connected and layout and name not in due:
                remembered[name] = layout
        state = now
        for name in [n for n, (t, _) in due.items() if t <= time.monotonic()]:
            _, attempt = due.pop(name)
            if not state[name][0]:
                continue
            layout = state[name][1] or remembered.get(name)
            ok = relight(name, layout) if layout else configure(name)
            state = snapshot(d, root)
            lit = state[name][0] and state[name][1] is not None
            if not (ok and lit) and attempt + 1 < len(SETTLE):
                log(f"{name} not lit yet, retrying in {SETTLE[attempt + 1]:.0f} s")
                due[name] = (time.monotonic() + SETTLE[attempt + 1], attempt + 1)


if __name__ == "__main__":
    main()
