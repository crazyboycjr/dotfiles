#!/bin/sh
# Screenshots that work while picom's desktop zoom is on.
#
# usage: screenshot.sh --region|--window --clipboard|--save [DIRECTORY]
#
# Unzoomed, this is plain xfce4-screenshooter. While zoomed, a screenshot tool
# would select in desktop coordinates but read the magnified screen, so:
#  - region: select on the zoomed screen with slop, zoom out for a moment and
#    capture that part of the desktop at its native size, as macOS does; without
#    slop, zoom out first and let xfce4-screenshooter select;
#  - window: capture the active window's own pixels, which are never zoomed.

mode=$1 target=$2 directory=${3:-$(xdg-user-dir PICTURES)}

get_zoom() {
	xprop -root -notype _PICOM_ZOOM 2>/dev/null | sed -n 's/^_PICOM_ZOOM = \([0-9]*\)$/\1/p'
}
set_zoom() { xprop -root -f _PICOM_ZOOM 32c -set _PICOM_ZOOM "$1"; }

zoom=$(get_zoom)
if [ "${zoom:-65536}" -le 65536 ]; then
	exec xfce4-screenshooter "$@"
fi

# The zoom eases out in about 0.3 s
zoom_out() {
	set_zoom 65536
	sleep 0.4
}
# Zoom back in, unless the zoom was changed meanwhile
zoom_back() {
	[ "$(get_zoom)" = 65536 ] && set_zoom "$zoom"
}

shot=$(mktemp --suffix=.png)
trap 'rm -f "$shot"' EXIT

case $mode in
--region)
	if ! command -v slop > /dev/null; then
		zoom_out
		xfce4-screenshooter "$@"
		zoom_back
		exit
	fi
	geometry=$(slop -f '%wx%h+%x+%y') || exit 0
	zoom_out
	import -window root -crop "$geometry" +repage "$shot"
	zoom_back
	;;
--window)
	window=$(xprop -root -notype _NET_ACTIVE_WINDOW | awk '{print $NF}')
	import -window "$window" "$shot"
	;;
*)
	exec xfce4-screenshooter "$@"
	;;
esac

case $target in
--clipboard) xclip -selection clipboard -t image/png < "$shot" ;;
--save)
	mkdir -p "$directory"
	cp "$shot" "$directory/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
	;;
esac
