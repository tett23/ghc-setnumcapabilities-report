#!/bin/bash
# Build GHC master (unpatched) with hadrian, flavour quick, on the Mac, using nix for alex/happy/autoconf.
set -e
D=/Users/tett23/repositories/src/gitlab.haskell.org/ghc/ghc
cd $D
export PATH=/Users/tett23/.ghcup/bin:$PATH
export GHC=/Users/tett23/.ghcup/bin/ghc-9.14.1
git log --oneline -1
GMPDEV=$(nix build --no-link --print-out-paths nixpkgs#gmp.dev); GMPLIB=$(nix build --no-link --print-out-paths nixpkgs#gmp); export GMPDEV GMPLIB; echo "gmp: $GMPDEV $GMPLIB"
nix shell nixpkgs#autoconf nixpkgs#automake nixpkgs#haskellPackages.alex nixpkgs#haskellPackages.happy --command bash -c '
set -e
export PATH=/Users/tett23/.ghcup/bin:$PATH
echo "== boot"; ./boot > boot.log 2>&1 || { tail -20 boot.log; exit 1; }
echo "== configure"; ./configure GHC=/Users/tett23/.ghcup/bin/ghc-9.14.1 --with-gmp-includes=$GMPDEV/include --with-gmp-libraries=$GMPLIB/lib > configure.log 2>&1 || { tail -40 configure.log; exit 1; }
grep -n -i "Bootstrapping using\|Using (bootstrap) GHC\|alex\|happy\|gmp" configure.log | head -12
echo "== hadrian build (quick)"; time hadrian/build -j10 --flavour=quick --docs=none > hadrian.log 2>&1 || { tail -60 hadrian.log; exit 1; }
tail -3 hadrian.log
ls -la _build/stage1/bin/ghc
_build/stage1/bin/ghc --version
'
echo HADRIAN BUILD DONE
