#!/usr/bin/env bash
set -e
cd $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

nodemon -w . -e sh -V --delay .2 -x reap -- -x $@
