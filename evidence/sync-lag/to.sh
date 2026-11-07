#!/bin/bash
# to.sh SECONDS cmd args...  : run cmd with a time limit; prints TIMEOUT if killed
to=$1; shift
"$@" & pid=$!
t=0; while [ $t -lt $((to*10)) ] && kill -0 $pid 2>/dev/null; do sleep 0.1; t=$((t+1)); done
if kill -0 $pid 2>/dev/null; then kill -9 $pid; wait $pid 2>/dev/null; echo "TIMEOUT after ${to}s: $*"; else wait $pid; fi
