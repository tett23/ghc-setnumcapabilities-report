#!/bin/bash
# macOS variant. usage: runmany-mac.sh LABEL N TIMEOUT MODE ROUNDS M W [RTS opts...]
label=$1; n=$2; to=$3; mode=$4; rounds=$5; m=$6; w=$7; shift 7
cd "$(dirname "$0")"
cpu_of() { ps -p $1 -o time= 2>/dev/null | awk -F'[:.]' '{ if (NF>=3) print $1*60+$2; else print 0 }'; }
hang=0; busy=0; ok=0; other=0
: > log-$label.txt
for i in $(seq 1 $n); do
  ./caprace $mode $rounds $m $w +RTS "$@" -RTS > out-$label.txt 2>&1 &
  pid=$!
  t=0
  while [ $t -lt $((to*10)) ] && kill -0 $pid 2>/dev/null; do sleep 0.1; t=$((t+1)); done
  if kill -0 $pid 2>/dev/null; then
    c1=$(cpu_of $pid); sleep 3; c2=$(cpu_of $pid); d=$((c2-c1))
    if ! kill -0 $pid 2>/dev/null; then wait $pid; ok=$((ok+1)); echo "run $i SLOW-OK" >> log-$label.txt; continue; fi
    if [ $d -lt 1 ]; then hang=$((hang+1)); kind=IDLE-HANG; else busy=$((busy+1)); kind=BUSY-TIMEOUT; fi
    echo "run $i $kind cpu_s_3s=$d last=[$(tail -1 out-$label.txt)]" >> log-$label.txt
    kill -9 $pid; wait $pid 2>/dev/null
  else
    wait $pid; rc=$?
    if [ $rc -eq 0 ]; then ok=$((ok+1)); else other=$((other+1)); echo "run $i rc=$rc $(tail -1 out-$label.txt)" >> log-$label.txt; fi
  fi
done
echo "RESULT(host mac 10cpu) $label mode=$mode rounds=$rounds M=$m W=$w rts=[$*] n=$n ok=$ok idle_hang=$hang busy_timeout=$busy other=$other" | tee -a log-$label.txt
