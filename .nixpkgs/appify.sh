#!/bin/bash

# make sure it is using GNU's cp
# CP="nix-shell -p coreutils cp"

baseDir="$HOME/Applications/Nix Apps"
# echo $baseDir

[ -d "$baseDir" ] && rm -rf "$baseDir"
mkdir -p "$baseDir"

nixAppsDir="$HOME/.nix-profile/Applications"
for app in "${nixAppsDir}"/*; do
	appFile=`readlink -f "${app}"`
	# echo $appFile
	cp -fHRL "$appFile" "$baseDir"
	target="$baseDir/$(basename "$appFile")"
	chmod -R +w "$target"
done



# install fonts to ~/Library/Fonts
fontDir="$HOME/Library/Fonts"

nixFontDir="$HOME/.nix-profile/share/fonts"
for font in "${nixFontDir}"/*; do
	fontFile=`readlink -f "$font"`
	# echo $fontFile
	cp -fHRL "$fontFile" "$fontDir"
	target="$fontDir/$(basename "$fontFile")"
	chmod -R +w "$target"
done
