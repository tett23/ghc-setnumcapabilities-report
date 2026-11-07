#!/bin/bash
# usage: huntbusy-mac.sh LABEL ATTEMPTS WAIT MODE ROUNDS M W [RTS opts] -- first run still busy after WAIT s gets an lldb backtrace (twice, 5 s apart)
label=$1; attempts=$2; wait=$3; mode=$4; rounds=$5; m=$6; w=$7; shift 7
cd "$(dirname "$0")"
cpu_of() { ps -p $1 -o time= 2>/dev/null | awk -F'[:.]' '{ if (NF>=3) print $1*60+$2; else print 0 }'; }
for a in $(seq 1 $attempts); do
  ./caprace $mode $rounds $m $w +RTS "$@" -RTS > busy-$label.out 2>&1 &
  pid=$!
  t=0
  while [ $t -lt $((wait*10)) ] && kill -0 $pid 2>/dev/null; do sleep 0.1; t=$((t+1)); done
  if kill -0 $pid 2>/dev/null; then
    c1=$(cpu_of $pid); sleep 3; c2=$(cpu_of $pid); d=$((c2-c1))
    if ! kill -0 $pid 2>/dev/null; then wait $pid; echo "attempt $a: slow but finished"; continue; fi
    if [ $d -ge 1 ]; then
      echo "attempt $a: BUSY pid=$pid cpu_s_3s=$d"; cat busy-$label.out
      lldb -p $pid --batch -o "thread backtrace all" -o "detach" > busy-$label.lldb.txt 2>&1
      sleep 5
      lldb -p $pid --batch -o "thread backtrace all" -o "detach" > busy-$label.lldb2.txt 2>&1
      kill -9 $pid; wait $pid 2>/dev/null
      exit 0
    fi
    echo "attempt $a: idle hang, killing"; kill -9 $pid; wait $pid 2>/dev/null
  else
    wait $pid; echo "attempt $a: finished rc=$?"
  fi
done
echo "no busy case in $attempts attempts"; exit 1
