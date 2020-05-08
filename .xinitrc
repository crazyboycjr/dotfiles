#!/bin/sh

[[ -f ~/.Xresources ]] && xrdb -merge -I$HOME ~/.Xresources

# set keyboard repeat <delay> <rate>
xset r rate 200 36

# map control keys to caps lock
setxkbmap -option "ctrl:nocaps"

# keymap
[[ -e /usr/bin/xmodmap && -f ~/.Xmodmap ]] && xmodmap ~/.Xmodmap

if [ -d /etc/X11/xinit/xinitrc.d ]; then
  for f in /etc/X11/xinit/xinitrc.d/*; do
    [ -x "$f" ] && . "$f"
  done
  unset f
fi

# set screenlayout to my dormitory setting
# gpu=`optimus-manager --print-mode | awk 'NF {print $NF}'` # this is not working
location='dorm' # {dorm, lab, laptop}
gpu='nvidia' # {nvidia, intel}
source ~/.screenlayout/${location}-${gpu}.sh

# set background
feh --bg-fill ~/.xmonad/background.jpg

# start gnome keyring
/usr/bin/gnome-keyring-daemon --daemonize --login &
# /usr/lib/gnome-shell-calendar-server &
# /usr/bin/gnome-calendar --gapplication-service &

# start compositor
xcompmgr &

# start clipboard manager
xfce4-clipman &

# start power manager
xfce4-power-manager &

# start screen saver
gnome-screensaver &

# startup programs, todo: move to scripts
nm-applet &
dropbox &
optimus-manager-qt &
fcitx-autostart &
sogou-qimpanel &

# here xmonad is kept as default
session=${1:-xmonad}
case $session in
    xmonad            ) exec xmonad;;
    i3|i3wm           ) exec i3;;
    kde               ) exec startplasma-x11;;
    xfce|xfce4        ) exec startxfce4;;
    # No known session, try to run it as command
    *                 ) exec $1;;
esac
