#!/bin/sh
cd /t
cp /src/.plughang/Race.hs /t/
/root/.ghcup/bin/ghc-9.10.3 -O -threaded -rtsopts Race.hs -o race -outputdir raceo > /dev/null || exit 1
/root/.ghcup/bin/ghc-9.10.3 -O -threaded -rtsopts -debug Race.hs -o race-dbg -outputdir raceo-dbg > /dev/null || exit 1
LIMIT=60 sh /src/.plughang/caploop.sh 500 race-a /t/race +RTS -N4 -RTS 8 &
LIMIT=60 sh /src/.plughang/caploop.sh 500 race-b /t/race +RTS -N4 -RTS 8 &
wait
