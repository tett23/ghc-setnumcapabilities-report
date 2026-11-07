#!/bin/sh
# usage: ccrts.sh SRCDIR OUTDIR  — compiles SRCDIR/rts/Schedule.c for ways thr and thr_debug
set -e
S=/private/tmp/claude-501/-Users-tett23-Documents-ghc-setnumcapabilities-report/d8d33e82-28ba-4838-aa11-b12dd8bfb044/scratchpad
RTS=/Users/tett23/.ghcup/ghc/9.10.3/lib/ghc-9.10.3/lib/aarch64-osx-ghc-9.10.3/rts-1.0.2
cd "$1"; mkdir -p "$2"
for way in thr thr_debug; do
  if [ $way = thr ]; then extra="-O2 -fomit-frame-pointer"; else extra="-O0 -g -DDEBUG"; fi
  cc --target=arm64-apple-darwin -Qunused-arguments -c rts/Schedule.c -o "$2/Schedule.$way.o" $extra -g1 -Wall -Wextra -Wno-unused-parameter -Wno-sign-compare -fno-strict-aliasing -fno-common -fwrapv -DCOMPILING_RTS -DFS_NAMESPACE=rts -DTHREADED_RTS -Irts -Irts/include -I$RTS/include 2>"$2/cc.$way.log" || { echo "$way FAILED"; grep -v warning "$2/cc.$way.log" | head; exit 1; }
  echo "$way: ok ($(grep -c 'warning:' "$2/cc.$way.log") warnings)"
done
