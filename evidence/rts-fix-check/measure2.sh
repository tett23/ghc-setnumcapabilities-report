#!/bin/bash
S=/private/tmp/claude-501/-Users-tett23-Documents-ghc-setnumcapabilities-report/d8d33e82-28ba-4838-aa11-b12dd8bfb044/scratchpad
cd $S/test
for rm in "2 3" "3 2" "1 4"; do
  set -- $rm; R=$1; M=$2; tag=r${R}m${M}
  for v in orig fixed; do
    wd=60; [ $v = orig ] && wd=20
    sed -e "s/^rounds = 3/rounds = $R/" -e "s/^setters = 4/setters = $M/" -e "s/c_watchdog 60/c_watchdog $wd/" TNNNNN.hs > T_$tag.hs
    ghc-9.10.3 -O -threaded -rtsopts -fforce-recomp -L$S/lib-$v T_$tag.hs TNNNNN_c.c -o t2-$tag-$v -outputdir o2-$tag-$v >/dev/null 2>&1 || echo "build failed t2-$tag-$v"
    ghc-9.10.3 -threaded -debug -rtsopts -fforce-recomp -L$S/lib-$v T_$tag.hs TNNNNN_c.c -o t1-$tag-$v -outputdir o1-$tag-$v >/dev/null 2>&1 || echo "build failed t1-$tag-$v"
  done
  bash $S/runmany.sh ./t2-$tag-orig 10 30 +RTS -N2
  bash $S/runmany.sh ./t1-$tag-orig 10 30
  bash $S/runmany.sh ./t2-$tag-fixed 60 70 +RTS -N2
  bash $S/runmany.sh ./t1-$tag-fixed 60 70
done
echo MEASURE2 DONE
