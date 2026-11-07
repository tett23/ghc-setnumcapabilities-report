#!/bin/bash
# 1) unpatched threaded2 through the driver (revert, rebuild, test), 2) re-apply, rebuild,
# 3) loop the stage1-built test binaries 60x per way, patched.
set -e
D=/Users/tett23/repositories/src/gitlab.haskell.org/ghc/ghc
P=/Users/tett23/Documents/ghc-setnumcapabilities-report/mr/rts-Schedule.c.patch
S=/private/tmp/claude-501/-Users-tett23-Documents-ghc-setnumcapabilities-report/d8d33e82-28ba-4838-aa11-b12dd8bfb044/scratchpad
cd $D
export PATH=/Users/tett23/.ghcup/bin:$PATH
nix shell nixpkgs#autoconf nixpkgs#automake nixpkgs#haskellPackages.alex nixpkgs#haskellPackages.happy --command bash -c '
set -e
export PATH=/Users/tett23/.ghcup/bin:$PATH
git apply -R '"$P"'; echo "== reverted: $(git diff --stat | tail -1)"
hadrian/build -j10 --flavour=quick --docs=none > hadrian-revert.log 2>&1; tail -1 hadrian-revert.log
echo "== test, UNPATCHED, threaded2 forced"
hadrian/build -j10 --flavour=quick --docs=none test --only=TNNNNN --test-way=threaded2 > test-unpatched-threaded2.log 2>&1 || true
grep -n "Wrong exit\|giving up\|expected passes\|unexpected failures" test-unpatched-threaded2.log | head
git apply '"$P"'; echo "== re-applied: $(git diff --stat | tail -1)"
hadrian/build -j10 --flavour=quick --docs=none > hadrian-reapply.log 2>&1; tail -1 hadrian-reapply.log
'
echo "== loop the stage1-built binaries, patched"
mkdir -p $S/hloop && cd $S/hloop && cp $D/testsuite/tests/rts/TNNNNN.hs $D/testsuite/tests/rts/TNNNNN_c.c .
G=$D/_build/stage1/bin/ghc
$G -threaded -debug -rtsopts -fforce-recomp TNNNNN.hs TNNNNN_c.c -o t1 -outputdir o1 >/dev/null 2>&1
$G -O -threaded -rtsopts -fforce-recomp TNNNNN.hs TNNNNN_c.c -o t2 -outputdir o2 >/dev/null 2>&1
$G --version
bash $S/runmany.sh ./t1 60 70
bash $S/runmany.sh ./t2 60 70 +RTS -N2
echo FINAL DONE
