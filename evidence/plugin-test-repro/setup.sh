#!/bin/sh
# runs inside the plughang container
set -eu
export PATH=/root/.ghcup/bin:$PATH
mkdir -p /w
cd /src
tar --exclude=./dist-newstyle --exclude=./.plughang --exclude=./cabal.project.local -cf - . | tar -C /w -xf -
cd /w
sh scripts/fetch-wasmtime.sh
cat cabal.project.local
cabal --version
cabal build -j3 -w ghc-9.10.3 golem-plugin:test:golem-plugin-test > /w/build.log 2>&1
cabal list-bin -w ghc-9.10.3 golem-plugin:test:golem-plugin-test
