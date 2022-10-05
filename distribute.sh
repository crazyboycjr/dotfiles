#!/usr/bin/env bash

WORKDIR=`dirname $(realpath $0)`
cd $WORKDIR

HOMEDIR=/home/cjr
SYSROOT=/
CP="rsync -aAXHv"

for f in `git ls-files`; do
	if [[ $f =~ collect.sh|distribute.sh|README|.gitignore ]]; then continue; fi
	if [[ $f == system/* ]]; then
		$CP $f ${SYSROOT}${f#"system/"}
	else
		$CP $f ${HOMEDIR}/$f
	fi
done
