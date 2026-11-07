#!/bin/sh
# caploop.sh N TAG BIN args...  : runs BIN N times with a 60 s watchdog, gdb on a hang
N=$1; TAG=$2; shift 2
OUT=/t/out; mkdir -p $OUT
ok=0; hang=0; i=0
while [ $i -lt $N ]; do
  i=$((i+1))
  "$@" > $OUT/$TAG.cur 2>&1 &
  pid=$!
  t=0
  while kill -0 $pid 2>/dev/null && [ $t -lt ${LIMIT:-240} ]; do sleep 0.25; t=$((t+1)); done
  if kill -0 $pid 2>/dev/null; then
    hang=$((hang+1))
    gdb -p $pid -batch -ex "set pagination off" -ex "thread apply all bt" > $OUT/$TAG.hang$hang.bt 2>&1
    cp $OUT/$TAG.cur $OUT/$TAG.hang$hang.out
    kill -9 $pid; wait $pid 2>/dev/null
  else
    if wait $pid; then ok=$((ok+1)); else cp $OUT/$TAG.cur $OUT/$TAG.fail$i.out; fi
  fi
  echo "$TAG i=$i ok=$ok hang=$hang" > $OUT/$TAG.status
done
echo done >> $OUT/$TAG.status
