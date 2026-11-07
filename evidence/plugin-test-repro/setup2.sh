#!/bin/sh
# runs inside the plughang container: Debian packages from deb.debian.org, then the build
set -eu
export PATH=/root/.ghcup/bin:$PATH
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates git > /dev/null
cd /w
cabal build -j3 -w ghc-9.10.3 golem-plugin:test:golem-plugin-test > /w/build.log 2>&1
cabal list-bin -w ghc-9.10.3 golem-plugin:test:golem-plugin-test
