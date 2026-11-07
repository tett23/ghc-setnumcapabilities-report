#!/bin/bash
# Variants that keep rounds=3 setters=4 but change the GC pressure from the workers:
#  w0   : no worker threads at all (only the main thread's performGC after each round)
#  nogc : 4 allocating workers, but they never call performGC
S=/private/tmp/claude-501/-Users-tett23-Documents-ghc-setnumcapabilities-report/d8d33e82-28ba-4838-aa11-b12dd8bfb044/scratchpad
cd $S/test
for tag in w0 nogc; do
  for v in orig fixed; do
    wd=60; [ $v = orig ] && wd=20
    case $tag in
      w0)   sed -e "s/^workers = 4/workers = 0/" -e "s/c_watchdog 60/c_watchdog $wd/" TNNNNN.hs > T_$tag.hs ;;
      nogc) sed -e '/when (i `mod` 400 == 0) performGC/d' -e "s/c_watchdog 60/c_watchdog $wd/" TNNNNN.hs > T_$tag.hs ;;
    esac
    ghc-9.10.3 -O -threaded -rtsopts -fforce-recomp -L$S/lib-$v T_$tag.hs TNNNNN_c.c -o t2-$tag-$v -outputdir o2-$tag-$v >/dev/null 2>&1 || echo "build failed t2-$tag-$v"
    ghc-9.10.3 -threaded -debug -rtsopts -fforce-recomp -L$S/lib-$v T_$tag.hs TNNNNN_c.c -o t1-$tag-$v -outputdir o1-$tag-$v >/dev/null 2>&1 || echo "build failed t1-$tag-$v"
  done
  bash $S/runmany.sh ./t2-$tag-orig 10 30 +RTS -N2
  bash $S/runmany.sh ./t1-$tag-orig 10 30
  bash $S/runmany.sh ./t2-$tag-fixed 60 70 +RTS -N2
  bash $S/runmany.sh ./t1-$tag-fixed 60 70
done
echo MEASURE3 DONE
