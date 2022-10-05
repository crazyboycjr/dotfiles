#!/usr/bin/env bash

WORKDIR=`dirname $(realpath $0)`
cd $WORKDIR

HOMEDIR=/home/cjr
SYSROOT=/
CP="cp -v"

for f in `git ls-files`; do
	if [[ $f =~ collect.sh|distribute.sh|README|.gitignore ]]; then continue; fi
	if [[ $f == system/* ]]; then
		$CP ${SYSROOT}${f#"system/"} $f
	else
		$CP ${HOMEDIR}/$f $f
	fi
done
