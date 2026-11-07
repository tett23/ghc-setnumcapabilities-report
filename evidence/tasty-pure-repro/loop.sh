#!/bin/sh
# loop.sh TAG N LIMIT_SECONDS DIR CMD...  : runs CMD (in DIR) N times; on a hang
# (still alive after LIMIT seconds) takes a gdb backtrace of all threads.
TAG=$1; N=$2; LIMIT=$3; DIR=$4; shift 4
OUT=/w2/out; mkdir -p $OUT
cd "$DIR" || exit 1
ok=0; fail=0; hang=0; i=0
while [ $i -lt $N ]; do
  i=$((i+1))
  "$@" > $OUT/$TAG.cur 2>&1 &
  pid=$!
  t=0
  while kill -0 $pid 2>/dev/null && [ $t -lt $((LIMIT*4)) ]; do sleep 0.25; t=$((t+1)); done
  if kill -0 $pid 2>/dev/null; then
    hang=$((hang+1))
    gdb -p $pid -batch -ex "set pagination off" -ex "info threads" -ex "thread apply all bt" > $OUT/$TAG.hang$hang.bt 2>&1
    cp $OUT/$TAG.cur $OUT/$TAG.hang$hang.out
    kill -9 $pid; wait $pid 2>/dev/null
  else
    if wait $pid; then ok=$((ok+1)); else fail=$((fail+1)); cp $OUT/$TAG.cur $OUT/$TAG.fail$fail.out; fi
  fi
  echo "$TAG i=$i ok=$ok fail=$fail hang=$hang" > $OUT/$TAG.status
done
echo done >> $OUT/$TAG.status
