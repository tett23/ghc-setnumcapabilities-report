#!/bin/sh
# Runs inside verify-a-1 (Debian 13 aarch64, 2 CPUs, GHC 9.10.3). Expects /root/fixcheck with:
#   rts-9.10.3/ rts-9.10.3-fixed/ (source trees), TNNNNN.hs TNNNNN_c.c runmany.sh
set -e
export PATH=/root/.ghcup/bin:$PATH
cd /root/fixcheck
LIBDIR=$(ghc --print-libdir)
RTS=$(ls -d $LIBDIR/aarch64-linux-ghc-9.10.3/rts-1.0.2* | head -1)
echo "RTS dir: $RTS"; ls $RTS | grep thr
for v in orig fixed; do
  src=rts-9.10.3; [ $v = fixed ] && src=rts-9.10.3-fixed
  mkdir -p objs-$v lib-$v
  for way in thr thr_debug; do
    if [ $way = thr ]; then extra="-O2 -fomit-frame-pointer"; else extra="-O0 -g -DDEBUG"; fi
    (cd $src && gcc -c rts/Schedule.c -o ../objs-$v/Schedule.$way.o $extra -g1 -Wall -Wextra -Wno-unused-parameter -Wno-sign-compare -fno-strict-aliasing -fno-common -fwrapv -DCOMPILING_RTS -DFS_NAMESPACE=rts -DTHREADED_RTS -Irts -Irts/include -I$RTS/include 2>objs-$v.cc.$way.log) || { echo "compile failed $v $way"; grep -v warning objs-$v.cc.$way.log | head; exit 1; }
    cp $RTS/libHSrts-1.0.2_$way.a lib-$v/ && cp objs-$v/Schedule.$way.o lib-$v/Schedule.${way}_o && (cd lib-$v && ar rs libHSrts-1.0.2_$way.a Schedule.${way}_o)
  done
  echo "$v: objects built and swapped"
done
# symbol check of the control object against the shipped one
mkdir -p shipped && (cd shipped && ar x $RTS/libHSrts-1.0.2_thr.a Schedule.thr_o)
nm shipped/Schedule.thr_o | grep ' [TDBU] ' | awk '{print $2,$3}' | sort -u > sym.shipped
nm objs-orig/Schedule.thr.o | grep ' [TDBU] ' | awk '{print $2,$3}' | sort -u > sym.orig
if diff sym.shipped sym.orig >/dev/null; then echo "symbol sets identical (control vs shipped)"; else echo "SYMBOL SETS DIFFER"; diff sym.shipped sym.orig | head; fi
sed 's/c_watchdog 60/c_watchdog 20/' TNNNNN.hs > T_wd20.hs
for v in orig fixed; do
  src=TNNNNN.hs; [ $v = orig ] && src=T_wd20.hs
  ghc -O -threaded -rtsopts -fforce-recomp -L/root/fixcheck/lib-$v $src TNNNNN_c.c -o t2-$v -outputdir o2-$v >/dev/null 2>&1
  ghc -threaded -debug -rtsopts -fforce-recomp -L/root/fixcheck/lib-$v $src TNNNNN_c.c -o t1-$v -outputdir o1-$v >/dev/null 2>&1
  for b in t1-$v t2-$v; do printf '%s setNumCapabilities insns: ' $b; objdump -d $b | awk '/<setNumCapabilities>:/{f=1;next} f&&/^[0-9a-f]+ </{exit} f' | wc -l; done
done
bash runmany.sh ./t2-orig 10 30 +RTS -N2
bash runmany.sh ./t1-orig 10 30
bash runmany.sh ./t2-fixed 60 70 +RTS -N2
bash runmany.sh ./t1-fixed 60 70
echo LINUX CHECK DONE
