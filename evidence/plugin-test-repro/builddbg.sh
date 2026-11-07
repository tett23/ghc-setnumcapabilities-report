#!/bin/sh
# debug-RTS build of golem-plugin-test in a copy (/w2) of the container tree
set -eu
export PATH=/root/.ghcup/bin:$PATH
rm -rf /w2
mkdir /w2
cd /w
tar --exclude=./dist-newstyle --exclude=./loops -cf - . | tar -C /w2 -xf -
cd /w2
sed -i 's|/w/third_party|/w2/third_party|g' cabal.project.local
sed -i 's|^  ghc-options:      -threaded$|  ghc-options:      -threaded -debug -rtsopts|' modules/golem-plugin/golem-plugin.cabal
grep -n "debug" modules/golem-plugin/golem-plugin.cabal
cabal build -j2 -w ghc-9.10.3 golem-plugin:test:golem-plugin-test > /w2/build.log 2>&1 || { tail -30 /w2/build.log; exit 1; }
cabal list-bin -w ghc-9.10.3 golem-plugin:test:golem-plugin-test
