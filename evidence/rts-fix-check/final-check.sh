#!/bin/bash
# Final test files, Mac: unfixed (20 s watchdog) 10 runs per way, fixed 60 runs per way.
S=/private/tmp/claude-501/-Users-tett23-Documents-ghc-setnumcapabilities-report/d8d33e82-28ba-4838-aa11-b12dd8bfb044/scratchpad
cd $S/final
for v in orig fixed; do
  src=TNNNNN.hs; [ $v = orig ] && src=T_wd20.hs
  ghc-9.10.3 -O -threaded -rtsopts -fforce-recomp -L$S/lib-$v $src TNNNNN_c.c -o t2-$v -outputdir o2-$v >/dev/null 2>&1 || echo "build failed t2-$v"
  ghc-9.10.3 -threaded -debug -rtsopts -fforce-recomp -L$S/lib-$v $src TNNNNN_c.c -o t1-$v -outputdir o1-$v >/dev/null 2>&1 || echo "build failed t1-$v"
  for b in t1-$v t2-$v; do printf '%s setNumCapabilities asm lines: ' $b; otool -tV $b | awk '/^_setNumCapabilities:/{f=1} f&&/^_[A-Za-z]/&&!/^_setNumCapabilities:/{exit} f' | wc -l; done
done
bash $S/runmany.sh ./t2-orig 10 30 +RTS -N2
bash $S/runmany.sh ./t1-orig 10 30
bash $S/runmany.sh ./t2-fixed 60 70 +RTS -N2
bash $S/runmany.sh ./t1-fixed 60 70
echo FINAL MAC DONE
