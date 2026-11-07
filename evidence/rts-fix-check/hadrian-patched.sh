#!/bin/bash
# Rebuild with the patch applied and run the test through the driver, then loop the built binaries.
set -e
D=/Users/tett23/repositories/src/gitlab.haskell.org/ghc/ghc
cd $D
export PATH=/Users/tett23/.ghcup/bin:$PATH
nix shell nixpkgs#autoconf nixpkgs#automake nixpkgs#haskellPackages.alex nixpkgs#haskellPackages.happy --command bash -c '
set -e
export PATH=/Users/tett23/.ghcup/bin:$PATH
echo "== rebuild"; time hadrian/build -j10 --flavour=quick --docs=none > hadrian-patched.log 2>&1 || { tail -40 hadrian-patched.log; exit 1; }
tail -2 hadrian-patched.log
echo "== test, patched"; time hadrian/build -j10 --flavour=quick --docs=none test --only=TNNNNN > test-patched.log 2>&1 || true
grep -n "TNNNNN\|unexpected\|expected passes\|Unexpected" test-patched.log | head -20
echo "== test, patched, threaded2 way forced"; time hadrian/build -j10 --flavour=quick --docs=none test --only=TNNNNN --test-way=threaded2 > test-patched-threaded2.log 2>&1 || true
grep -n "TNNNNN\|unexpected\|expected passes\|Unexpected" test-patched-threaded2.log | head -20
'
echo PATCHED DONE
