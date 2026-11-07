#!/bin/bash
S=/private/tmp/claude-501/-Users-tett23-Documents-ghc-setnumcapabilities-report/d8d33e82-28ba-4838-aa11-b12dd8bfb044/scratchpad
cd $S/build
for v in orig fixed; do ghc-9.10.3 -O1 -threaded -rtsopts -fforce-recomp -L$S/lib-$v CapRace.hs -o caprace-$v >/dev/null 2>&1; done
cd $S/test
for v in orig fixed; do
  ghc-9.10.3 -O -threaded -rtsopts -fforce-recomp -L$S/lib-$v TNNNNN.hs TNNNNN_c.c -o t2-$v -outputdir o2-$v >/dev/null 2>&1
  ghc-9.10.3 -threaded -debug -rtsopts -fforce-recomp -L$S/lib-$v TNNNNN.hs TNNNNN_c.c -o t1-$v -outputdir o1-$v >/dev/null 2>&1
done
for b in $S/build/caprace-orig $S/build/caprace-fixed t1-orig t1-fixed t2-orig t2-fixed; do
  printf '%s setNumCapabilities asm lines: ' $b; otool -tV $b | awk '/^_setNumCapabilities:/{f=1} f&&/^_[A-Za-z]/&&!/^_setNumCapabilities:/{exit} f' | wc -l
done
bash $S/runmany.sh $S/build/caprace-orig 20 10 conc 3 4 4 +RTS -N1
bash $S/runmany.sh $S/build/caprace-fixed 50 30 conc 3 4 4 +RTS -N1
# the test's own watchdog is 60 s; give runmany a larger timeout so a watchdog exit counts as "other"
bash $S/runmany.sh ./t2-orig 20 70 +RTS -N2
bash $S/runmany.sh ./t2-fixed 100 70 +RTS -N2
bash $S/runmany.sh ./t1-orig 10 70
bash $S/runmany.sh ./t1-fixed 50 70
echo MEASURE DONE
