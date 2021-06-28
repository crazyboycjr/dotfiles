#!/bin/bash

# make sure it is using GNU's cp
# CP="nix-shell -p coreutils cp"

baseDir="$HOME/Applications/Nix Apps"
# echo $baseDir

[ -d "$baseDir" ] && rm -rf "$baseDir"
mkdir -p "$baseDir"

nixAppsDir="$HOME/.nix-profile/Applications"
for app in ${nixAppsDir}/*; do
	appFile=`readlink -f "${app}"`
	# echo $appFile
	target="$baseDir/$(basename "$appFile")"
	cp -fHRL "$appFile" "$baseDir"
	chmod -R +w "$target"
done
