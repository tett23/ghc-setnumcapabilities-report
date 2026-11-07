#!/bin/bash
cd "$(dirname "$0")"
rm -f log-*.txt
T=4
( ./runmany-mac.sh e-conc2to16 200 $T conc 1 14 4 -N2; ./runmany-mac.sh serial 200 $T serial 3 4 4 -N1; ./runmany-mac.sh dec 200 $T dec 3 4 4 -N1; ./runmany-mac.sh noopN8 200 $T noop 3 4 4 -N8; ./runmany-mac.sh serial2to16 200 $T serial 1 14 4 -N2 ) > g1.log 2>&1 &
( ./runmany-mac.sh conc 200 $T conc 3 4 4 -N1; ./runmany-mac.sh conc-qg 100 $T conc 3 4 4 -N1 -qg; ./runmany-mac.sh same 100 $T same 3 4 4 -N1; ./runmany-mac.sh mixed 100 $T mixed 3 4 4 -N1 ) > g2.log 2>&1 &
wait
echo BATCH DONE
