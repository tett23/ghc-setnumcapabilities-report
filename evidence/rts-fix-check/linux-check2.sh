#!/bin/sh
# rounds=6 variant on the 2-CPU container: does more rounds make the unfixed failure more reliable, and does the fixed run stay fast?
set -e
export PATH=/root/.ghcup/bin:$PATH
cd /root/fixcheck
sed -e 's/^rounds = 3/rounds = 6/' -e 's/c_watchdog 60/c_watchdog 20/' TNNNNN.hs > T_r6_wd20.hs
sed -e 's/^rounds = 3/rounds = 6/' TNNNNN.hs > T_r6.hs
ghc -O -threaded -rtsopts -fforce-recomp -L/root/fixcheck/lib-orig T_r6_wd20.hs TNNNNN_c.c -o t2-r6-orig -outputdir o2-r6-orig >/dev/null 2>&1
ghc -threaded -debug -rtsopts -fforce-recomp -L/root/fixcheck/lib-orig T_r6_wd20.hs TNNNNN_c.c -o t1-r6-orig -outputdir o1-r6-orig >/dev/null 2>&1
ghc -O -threaded -rtsopts -fforce-recomp -L/root/fixcheck/lib-fixed T_r6.hs TNNNNN_c.c -o t2-r6-fixed -outputdir o2-r6-fixed >/dev/null 2>&1
ghc -threaded -debug -rtsopts -fforce-recomp -L/root/fixcheck/lib-fixed T_r6.hs TNNNNN_c.c -o t1-r6-fixed -outputdir o1-r6-fixed >/dev/null 2>&1
bash runmany.sh ./t2-r6-orig 20 30 +RTS -N2
bash runmany.sh ./t1-r6-orig 20 30
bash runmany.sh ./t2-r6-fixed 60 70 +RTS -N2
bash runmany.sh ./t1-r6-fixed 60 70
echo LINUX CHECK2 DONE
