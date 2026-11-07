#!/bin/bash
# Rebuilds the swap infrastructure (the scratchpad was cleared) and adds a 'nostop' variant:
# the fixed Schedule.c with the stopTimer()/startTimer() pair removed from setNumCapabilities.
set -e
S=/private/tmp/claude-501/-Users-tett23-Documents-ghc-setnumcapabilities-report/d8d33e82-28ba-4838-aa11-b12dd8bfb044/scratchpad
E=/Users/tett23/Documents/ghc-setnumcapabilities-report/evidence/rts-fix-check
RTS=/Users/tett23/.ghcup/ghc/9.10.3/lib/ghc-9.10.3/lib/aarch64-osx-ghc-9.10.3/rts-1.0.2
rm -rf $S/rts-9.10.3 $S/rts-9.10.3-fixed $S/rts-9.10.3-nostop
mkdir -p $S/rts-9.10.3 && (cd /Users/tett23/repositories/src/github.com/ghc/ghc && git archive ghc-9.10.3-release rts | tar -x -C $S/rts-9.10.3)
cp -R $S/rts-9.10.3 $S/rts-9.10.3-fixed
python3 -I $E/patch.py $S/rts-9.10.3/rts/Schedule.c $S/rts-9.10.3-fixed/rts/Schedule.c
cp -R $S/rts-9.10.3-fixed $S/rts-9.10.3-nostop
python3 -I - <<'PY'
p='/private/tmp/claude-501/-Users-tett23-Documents-ghc-setnumcapabilities-report/d8d33e82-28ba-4838-aa11-b12dd8bfb044/scratchpad/rts-9.10.3-nostop/rts/Schedule.c'
s=open(p).read()
a=s.index('setNumCapabilities (uint32_t new_n_capabilities USED_IF_THREADS)')
b=s.index('#endif // THREADED_RTS', a)
body=s[a:b]
n1=body.count('    stopTimer();\n'); n2=body.count('startTimer();\n')
body=body.replace('    stopTimer();\n','    /* stopTimer() removed (experiment: master dropped it in 341ed474) */\n').replace('        startTimer();\n','').replace('    startTimer();\n','')
print("nostop: removed stopTimer x%d, startTimer x%d"%(n1,n2))
open(p,'w').write(s[:a]+body+s[b:])
PY
for v in orig fixed nostop; do
  src=$S/rts-9.10.3; [ $v = fixed ] && src=$S/rts-9.10.3-fixed; [ $v = nostop ] && src=$S/rts-9.10.3-nostop
  sh $E/ccrts.sh $src $S/objs-$v
  mkdir -p $S/lib-$v; cd $S/lib-$v
  for w in thr thr_debug; do cp $RTS/libHSrts-1.0.2_$w.a . && cp $S/objs-$v/Schedule.$w.o Schedule.${w}_o && ar rs libHSrts-1.0.2_$w.a Schedule.${w}_o 2>/dev/null; done
done
cd $S/synclag
for v in orig fixed nostop; do
  ghc-9.10.3 -O -threaded -rtsopts -fforce-recomp -L$S/lib-$v SyncLag.hs -o synclag-O-$v -outputdir oO-$v >/dev/null 2>&1
  ghc-9.10.3 -threaded -debug -rtsopts -fforce-recomp -L$S/lib-$v SyncLag.hs -o synclag-dbg-$v -outputdir odbg-$v >/dev/null 2>&1
  for b in synclag-O-$v synclag-dbg-$v; do printf '%s asm lines: ' $b; otool -tV $b | awk '/^_setNumCapabilities:/{f=1} f&&/^_[A-Za-z]/&&!/^_setNumCapabilities:/{exit} f' | wc -l; done
done
for rep in 1 2 3; do
  for v in orig fixed nostop; do
    for b in synclag-O-$v synclag-dbg-$v; do printf '%s: ' $b; bash $S/to.sh 120 ./$b caps 50 4 +RTS -N2; done
  done
done
echo REBUILD-NOSTOP DONE
