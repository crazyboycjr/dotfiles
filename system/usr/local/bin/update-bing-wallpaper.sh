#!/usr/bin/env bash

OUT=`mktemp` && curl -s -L https://cjr.host/bing4k -o $OUT && feh --bg-scale $OUT
echo "Wallpaper updated"
