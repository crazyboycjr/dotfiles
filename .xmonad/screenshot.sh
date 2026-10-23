#!/bin/sh
# Screenshots that work while picom's desktop zoom is on.
#
# usage: screenshot.sh --region|--window --clipboard|--save [DIRECTORY]
#
# A screenshot tool selects in desktop coordinates but reads the screen, which is
# magnified while zoomed. So a region shot zooms out to 1x first, lets
# xfce4-screenshooter select on the plain screen and zooms back in afterwards; a
# window shot captures the active window's own pixels, which are never zoomed.
# Unzoomed, both are plain xfce4-screenshooter.

mode=$1 target=$2 directory=${3:-$(xdg-user-dir PICTURES)}

get_zoom() {
	xprop -root -notype _PICOM_ZOOM 2>/dev/null | sed -n 's/^_PICOM_ZOOM = \([0-9]*\)$/\1/p'
}
set_zoom() { xprop -root -f _PICOM_ZOOM 32c -set _PICOM_ZOOM "$1"; }

zoom=$(get_zoom)
if [ "${zoom:-65536}" -le 65536 ]; then
	exec xfce4-screenshooter "$@"
fi

case $mode in
--region)
	set_zoom 65536
	# The zoom eases out in about 0.3 s
	sleep 0.4
	xfce4-screenshooter "$@"
	# Zoom back in, unless the zoom was changed meanwhile
	[ "$(get_zoom)" = 65536 ] && set_zoom "$zoom"
	;;
--window)
	shot=$(mktemp --suffix=.png)
	trap 'rm -f "$shot"' EXIT
	window=$(xprop -root -notype _NET_ACTIVE_WINDOW | awk '{print $NF}')
	import -window "$window" "$shot"
	case $target in
	--clipboard) xclip -selection clipboard -t image/png < "$shot" ;;
	--save)
		mkdir -p "$directory"
		cp "$shot" "$directory/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
		;;
	esac
	;;
*)
	exec xfce4-screenshooter "$@"
	;;
esac
