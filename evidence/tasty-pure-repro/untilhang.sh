#!/bin/sh
# untilhang.sh TAG LIMIT BIN : run BIN until one run is alive after LIMIT s, then dump RTS state
TAG=$1; LIMIT=$2; BIN=$3
OUT=/w2/out; mkdir -p $OUT
i=0
while :; do
  i=$((i+1))
  "$BIN" > $OUT/$TAG.cur 2>&1 &
  pid=$!
  t=0
  while kill -0 $pid 2>/dev/null && [ $t -lt $((LIMIT*4)) ]; do sleep 0.25; t=$((t+1)); done
  if kill -0 $pid 2>/dev/null; then
    gdb -p $pid -batch -x /w2/repro/caps.gdb > $OUT/$TAG.state 2>&1
    echo "hang at run $i" >> $OUT/$TAG.state
    kill -9 $pid
    exit 0
  fi
  wait $pid
done
