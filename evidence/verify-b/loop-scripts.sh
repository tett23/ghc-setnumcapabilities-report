#!/bin/sh
# loop.sh BIN N TAG [args]  -- 15 s timeout per run
BIN=$1; N=$2; TAG=$3; shift 3; OUT=/v/repro/out; mkdir -p $OUT
ok=0; hang=0; fail=0; i=0
while [ $i -lt $N ]; do
  i=$((i+1))
  "$BIN" "$@" > $OUT/$TAG.cur 2>&1 & pid=$!
  t=0; while kill -0 $pid 2>/dev/null && [ $t -lt 60 ]; do sleep 0.25; t=$((t+1)); done
  if kill -0 $pid 2>/dev/null; then hang=$((hang+1)); gdb -p $pid -batch -ex "set pagination off" -ex "thread apply all bt" > $OUT/$TAG.hang$hang.bt 2>&1; gdb -p $pid -batch -x /v/off/dump.gdb > $OUT/$TAG.hang$hang.state 2>&1; cp $OUT/$TAG.cur $OUT/$TAG.hang$hang.out; kill -9 $pid; wait $pid 2>/dev/null
  else if wait $pid; then ok=$((ok+1)); else fail=$((fail+1)); fi; fi
  echo "$TAG i=$i ok=$ok fail=$fail hang=$hang" > $OUT/$TAG.status
done; echo done >> $OUT/$TAG.status

# ---- loop2.sh
#!/bin/sh
# loop2.sh BIN DIR N TAG [args...]  -- stdout+stderr to .cur; on hang: gdb bt, keep .out, kill; on fail keep .out
BIN=$1; DIR=$2; N=$3; TAG=$4; shift 4
OUT=/v/loops; LIMIT=${LIMIT:-480}
mkdir -p "$OUT"; cd "$DIR" || exit 1
ok=0; fail=0; hang=0; i=0
while [ $i -lt "$N" ]; do
  i=$((i+1))
  "$BIN" "$@" > "$OUT/$TAG.cur" 2>&1 &
  pid=$!
  t=0
  while kill -0 $pid 2>/dev/null && [ $t -lt "$LIMIT" ]; do sleep 0.25; t=$((t+1)); done
  if kill -0 $pid 2>/dev/null; then
    hang=$((hang+1))
    gdb -p $pid -batch -ex "set pagination off" -ex "info threads" -ex "thread apply all bt" > "$OUT/$TAG.hang$hang.bt" 2>&1
    gdb -p $pid -batch -x /v/off/dump.gdb > "$OUT/$TAG.hang$hang.state" 2>&1
    cp "$OUT/$TAG.cur" "$OUT/$TAG.hang$hang.out"
    kill -9 $pid; wait $pid 2>/dev/null
  else
    if wait $pid; then ok=$((ok+1)); else fail=$((fail+1)); cp "$OUT/$TAG.cur" "$OUT/$TAG.fail$fail.out"; fi
  fi
  echo "$TAG i=$i ok=$ok fail=$fail hang=$hang" > "$OUT/$TAG.status"
done
echo done >> "$OUT/$TAG.status"
