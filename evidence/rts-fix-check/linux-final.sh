#!/bin/sh
# Final test files in the 2-CPU container (lib-orig / lib-fixed already built by linux-check.sh).
set -e
export PATH=/root/.ghcup/bin:$PATH
cd /root/fixcheck/final
for v in orig fixed; do
  src=TNNNNN.hs; [ $v = orig ] && src=T_wd20.hs
  ghc -O -threaded -rtsopts -fforce-recomp -L/root/fixcheck/lib-$v $src TNNNNN_c.c -o t2-$v -outputdir o2-$v >/dev/null 2>&1
  ghc -threaded -debug -rtsopts -fforce-recomp -L/root/fixcheck/lib-$v $src TNNNNN_c.c -o t1-$v -outputdir o1-$v >/dev/null 2>&1
done
bash ../runmany.sh ./t2-orig 20 30 +RTS -N2
bash ../runmany.sh ./t1-orig 20 30
bash ../runmany.sh ./t2-fixed 60 70 +RTS -N2
bash ../runmany.sh ./t1-fixed 60 70
echo FINAL LINUX DONE
