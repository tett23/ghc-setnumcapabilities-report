#!/bin/bash
# Runs the stock debug build with -Ds (timestamped) until one run has a setNumCapabilities call over 1 s; keeps that trace.
S=/private/tmp/claude-501/-Users-tett23-Documents-ghc-setnumcapabilities-report/d8d33e82-28ba-4838-aa11-b12dd8bfb044/scratchpad
cd $S/synclag
for a in $(seq 1 25); do
  ./synclag-dbg caps 50 4 +RTS -N2 -Ds -RTS 2>&1 | perl -MTime::HiRes=time -ne 'BEGIN{$t0=time} printf "%9.1f %s", (time-$t0)*1000, $_' > trace-try.txt
  summary=$(grep '^ *[0-9.]* mode=' trace-try.txt | sed 's/^ *[0-9.]* //')
  mx=$(echo "$summary" | sed -n 's/.*max_ms=\([0-9.]*\).*/\1/p')
  echo "attempt $a: $summary"
  if [ -n "$mx" ] && [ "$(echo "$mx > 1000" | bc)" = 1 ]; then mv trace-try.txt trace-slow.txt; echo "kept trace-slow.txt"; break; fi
done
[ -f trace-slow.txt ] && awk 'NR>1{d=$1-p; if(d>100) printf "gap %.0f ms before line %d: %s\n", d, NR, $0} {p=$1}' trace-slow.txt | head
echo HUNT DONE
