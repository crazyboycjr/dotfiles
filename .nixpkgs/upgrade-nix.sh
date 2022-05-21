#!/usr/bin/env bash

function info {
	echo "$(tput bold)$(tput setaf 10)"$*"$(tput sgr 0)"
}

set -eu
builtin cd /nix/var/nix/profiles/per-user/$USER
LATEST_PROFILE=`readlink profile`
GENERATION=`readlink profile | grep -o '[0-9]\+'`
NEXT_GENERATION=`expr $GENERATION + 1`
SUFFIX=`date +%H-%m-%S`
TEMP_PROFILE="${LATEST_PROFILE}-upgrade-nix-${SUFFIX}"
info "Operating in temporary directory: ${TEMP_PROFILE}"

NEW_PROFILE="profile-${NEXT_GENERATION}-link"

ln -sf "${LATEST_PROFILE}" "${TEMP_PROFILE}"
info "Old profile ${LATEST_PROFILE}:"
nix profile list --profile ${TEMP_PROFILE}

# this will automatically create new profiles
nix profile remove --profile ${TEMP_PROFILE} legacyPackages.x86_64-linux.nixUnstable
nix profile remove --profile ${TEMP_PROFILE} legacyPackages.x86_64-linux.cacert
nix profile install --profile ${TEMP_PROFILE} nixpkgs#nixUnstable nixpkgs#cacert

RES_STORE_PATH=`readlink -f ${TEMP_PROFILE}`
ln -sfT ${RES_STORE_PATH} ${NEW_PROFILE}
ln -sfT ${NEW_PROFILE} profile

# remove temp dir on a successful upgrade
info "Removing temporary profiles..."
ls | grep profile | grep upgrade-nix | xargs rm -fv

info "New profile ${NEW_PROFILE}:"
nix profile list

info "Updating nix channel:"
nix-channel --update
