#!/bin/sh
# applies the patched test files from /src to /w and rebuilds the test
set -eu
export PATH=/root/.ghcup/bin:$PATH
cp /src/modules/golem-plugin/golem-plugin.cabal /w/modules/golem-plugin/
cp /src/modules/golem-plugin/test/ConcurrencySpec.hs /w/modules/golem-plugin/test/
cd /w
cabal build -j3 -w ghc-9.10.3 golem-plugin:test:golem-plugin-test > /w/build-fix.log 2>&1 || { tail -30 /w/build-fix.log; exit 1; }
B=$(cabal list-bin -w ghc-9.10.3 golem-plugin:test:golem-plugin-test)
cp "$B" /t/plugin-fixed
cd /w/modules/golem-plugin && /t/plugin-fixed | tail -3
