#!/usr/bin/env sh
# One bar per active monitor, the primary first so it gets the tray; logs go to journalctl -t polybar.

killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.1; done

for m in $(polybar -m | grep primary | cut -d: -f1) $(polybar -m | grep -v primary | cut -d: -f1); do
    MONITOR=$m setsid systemd-cat -t polybar polybar --reload main &
    sleep 0.1
done
