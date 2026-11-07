#!/bin/bash
# usage: runmany.sh BIN N TIMEOUT args...   (classifies ok / idle_hang / busy_timeout; prints max/avg time)
bin=$1; n=$2; to=$3; shift 3
cpu_of() { ps -p $1 -o time= 2>/dev/null | awk -F'[:.]' '{ if (NF>=3) print $1*60+$2; else print 0 }'; }
hang=0; busy=0; ok=0; other=0; maxt=0; sum=0
for i in $(seq 1 $n); do
  s=$(date +%s.%N)
  "$bin" "$@" > /dev/null 2>&1 & pid=$!
  t=0
  while [ $t -lt $((to*10)) ] && kill -0 $pid 2>/dev/null; do sleep 0.1; t=$((t+1)); done
  if kill -0 $pid 2>/dev/null; then
    c1=$(cpu_of $pid); sleep 3; c2=$(cpu_of $pid); d=$((c2-c1))
    if ! kill -0 $pid 2>/dev/null; then wait $pid; ok=$((ok+1)); continue; fi
    if [ $d -lt 1 ]; then hang=$((hang+1)); else busy=$((busy+1)); fi
    kill -9 $pid; wait $pid 2>/dev/null
  else
    wait $pid; rc=$?; e=$(date +%s.%N); el=$(echo "$e - $s" | bc)
    sum=$(echo "$sum + $el" | bc); if [ $(echo "$el > $maxt" | bc) = 1 ]; then maxt=$el; fi
    if [ $rc -eq 0 ]; then ok=$((ok+1)); else other=$((other+1)); fi
  fi
done
printf 'RESULT %s args=[%s] n=%d ok=%d idle_hang=%d busy_timeout=%d other=%d max_ok_time=%.2fs avg_ok_time=%.3fs\n' "$(basename $bin)" "$*" $n $ok $hang $busy $other $maxt $(echo "scale=3; $sum / ($ok+$other+0.0001)" | bc)
