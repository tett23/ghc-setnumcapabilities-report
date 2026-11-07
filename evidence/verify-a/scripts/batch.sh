#!/bin/bash
cd "$(dirname "$0")"
T=8
./runmany.sh conc     caprace 200 $T conc   3 4 4 -N1
./runmany.sh serial   caprace 200 $T serial 3 4 4 -N1
./runmany.sh dec      caprace 200 $T dec    3 4 4 -N1
./runmany.sh noopN8   caprace 200 $T noop   3 4 4 -N8
./runmany.sh conc-qg  caprace 100 $T conc   3 4 4 -N1 -qg
./runmany.sh same     caprace 100 $T same   3 4 4 -N1
./runmany.sh mixed    caprace 100 $T mixed  3 4 4 -N1
./runmany.sh conc-dbg caprace-debug 50 $T conc 3 4 4 -N1
echo BATCH DONE
