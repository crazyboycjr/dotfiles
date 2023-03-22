#!/usr/bin/env sh

export MONITOR=$(polybar -m|tail -1|sed -e 's/:.*$//g')

# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

if type "xrandr"; then
    PRIMARY=$(xrandr --query | grep " connected" | grep "primary" | cut -d" " -f1)
    OTHERS=$(xrandr --query | grep " connected" | grep -v "primary" | cut -d" " -f1)
    MONITOR=$PRIMARY TRAY_POS=right setsid polybar --reload main &
    for m in $OTHERS; do
      MONITOR=$m TRAY_POS=none setsid polybar --reload main &
    done
else
  setsid polybar --reload main &
fi
# exec polybar --reload main
