#!/bin/bash
# usage: huntbusy.sh LABEL BIN ATTEMPTS WAIT MODE ROUNDS M W [RTS opts] -- stops at first BUSY (still running, CPU>0) process, dumps with gdb twice
label=$1; bin=$2; attempts=$3; wait=$4; mode=$5; rounds=$6; m=$7; w=$8; shift 8
cd "$(dirname "$0")"
cpu_of() { awk '{print $14+$15}' /proc/$1/stat 2>/dev/null || echo 0; }
for a in $(seq 1 $attempts); do
  ./$bin $mode $rounds $m $w +RTS "$@" -RTS > hang-$label.out 2>&1 &
  pid=$!
  t=0
  while [ $t -lt $((wait*10)) ] && kill -0 $pid 2>/dev/null; do sleep 0.1; t=$((t+1)); done
  if kill -0 $pid 2>/dev/null; then
    c1=$(cpu_of $pid); sleep 2; c2=$(cpu_of $pid); d=$((c2-c1))
    if ! kill -0 $pid 2>/dev/null; then wait $pid; echo "attempt $a: slow but finished"; continue; fi
    if [ $d -ge 10 ]; then
      echo "attempt $a: BUSY pid=$pid cpu_ticks_2s=$d"; cat hang-$label.out
      gdb -q -batch -p $pid -x dump.gdb 2>&1 | grep -v "^\[New LWP\|^Reading symbols\|libthread_db\|^Using host\|^\[Thread debugging" > hang-$label.gdb.txt
      sleep 3
      gdb -q -batch -p $pid -x dump.gdb 2>&1 | grep -v "^\[New LWP\|^Reading symbols\|libthread_db\|^Using host\|^\[Thread debugging" > hang-$label.gdb2.txt
      kill -9 $pid; wait $pid 2>/dev/null
      exit 0
    fi
    echo "attempt $a: idle hang (cpu=$d), killing"; kill -9 $pid; wait $pid 2>/dev/null
  else
    wait $pid; echo "attempt $a: finished rc=$?"
  fi
done
echo "no busy case in $attempts attempts"; exit 1
