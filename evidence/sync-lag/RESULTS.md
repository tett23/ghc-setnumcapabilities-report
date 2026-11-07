# The "slow setNumCapabilities" phenomenon (HANDOFF item 2), 2026-11-06

Question: with no concurrent `setNumCapabilities` calls at all, why do
stop-the-world operations sometimes take seconds to minutes while other
threads allocate (the `busy_timeout` rows in verify-a, the slow tails in
`rts-fix-check`)?

## Reproducer: `SyncLag.hs`

`synclag MODE ITERS WORKERS`: `WORKERS` threads run an allocating loop and
never call `performGC`; the main thread times `ITERS` operations:
`gc` = `performGC`, `caps` = `setNumCapabilities` alternating n+1 / n
(serial, so the capability-leak bug cannot occur). Built with
`ghc-9.10.3 -O -threaded` (`synclag-O`) and `-threaded -debug`
(`synclag-dbg`), stock ghcup RTS. Mac, 10 cores. `to.sh` is the time limit.

## First scan (stock RTS, 4 workers, 50 operations)

| binary | mode | `-N` | result |
|---|---|---|---|
| `-O` | gc | 2 | max 1.4 ms, mean 1.3 ms |
| `-O` | caps | 2 | **not finished after 120 s** |
| `-O` | gc | 4 | max 1.5 ms |
| `-O` | caps | 4 | **not finished after 120 s** |
| debug | gc | 2 | max 1.6 ms |
| debug | caps | 2 | max 5122 ms, 2 of 50 over 100 ms |
| debug | gc | 4 | max 1.8 ms |
| debug | caps | 4 | **not finished after 120 s** |

So `performGC` is always fast; the stall is specific to
`setNumCapabilities`. In the debug build it is intermittent (per run: max
96 ms to 2.5 s over 8 runs, `hunt.log`); in the `-O` build, whose workers
allocate almost nothing (the list sum fuses into a non-allocating loop),
it does not finish at all.

## What the trace shows (`trace-dbg-N2-slow.txt`, debug build, `+RTS -N2 -Ds`, timestamps in ms)

The slow call (2502 ms, measured by the program) is "changing the number of
Capabilities from 2 to 3" at 55.7 ms. The RTS part is over by 56.4 ms:

- 55.7–55.8: sync, `grabbing all the capabilities (0/2) (1/2)`, `cap 2:
  initialised`.
- 56.1: `cap 1: created thread 10`, `new bound thread (10)`: this is
  `rts_evalIO(ioManagerCapabilitiesChanged_closure)` at the end of
  `setNumCapabilities` (Schedule.c:2378 in 9.10.3), run as a bound thread
  on the caller's capability 1, whose run queue also holds worker thread 9.
- 56.4: the bound task finishes a GC and `giving up capability 1 / passing
  capability 1 to worker`: thread 9 is at the head of the run queue and is
  not bound, so the bound task must hand the capability to a worker task.
- 56.5–2557.1: the worker runs thread 9, which stops every 6–9 ms with
  `stopped (yielding)` or `stopped (heap overflow)` and is immediately
  re-run: 12,000 trace lines, over 300 stops, never thread 10. Every
  `all threads` dump in that period lists thread 10 on capability 1 as
  "not blocked".
- 2557.1: `passing capability 1 to bound task`, thread 10 runs, finishes
  at once (`stopped (finished)`), and the call returns.

So the time is spent with the IO-manager helper thread runnable but
starved by one worker thread on the same capability.

## Why the worker never gives way: the timer is stopped

`scheduleHandleYield` (Schedule.c:1252) puts a yielding thread at the
*back* of the run queue only when `cap->context_switch` is set, and
otherwise at the *front* (`pushOnRunQueue`). The same holds for
`scheduleHandleHeapOverflow` (:1142). `context_switch` is set by the
timer tick (`handle_tick` → `contextSwitchAllCapabilities`, Timer.c:118),
and only when `timer_disabled == 0` (Timer.c:113), or at every scheduler
pass when `+RTS -C0` is given (Schedule.c:406).

`setNumCapabilities` in 9.10.3 calls `stopTimer()` (Schedule.c:2295)
before the sync and `startTimer()` (:2382) only *after*
`rts_evalIO(ioManagerCapabilitiesChanged_closure)` (:2378). While the
IO-manager helper runs, there are no ticks, so a worker thread that keeps
yielding (through GC interrupts or nursery exhaustion) is always put back
at the front of the queue, and the bound helper thread behind it never
runs. In the `-O` build the workers also barely allocate, so even the
GC-driven stops are rare and nothing ever lets the helper in.

The same `stopTimer()` … `notifyIOManagerCapabilitiesChanged()` …
`startTimer()` order is in `ghc-9.12.4-release` and `ghc-9.14.1-release`.
On `master` the `stopTimer()/startTimer()` pair was removed on 2026-06-12
(commit 341ed474, "Remove redundant use of stopTimer in
setNumCapabilities", which also notes it as a partial fix of #27105), so
master should not have this stall.

This also explains why `-fno-omit-yields` made no difference in
verify-a: the yields happen, but with the timer stopped each one puts the
thread back at the front.

## Confirmation experiments

See the sections appended below (`nostop` RTS variant; `+RTS -C0`).

### `+RTS -C0` on the stock RTS (same binaries, 4 workers, 50 calls, `-N2`)

`-C0` sets `context_switch` at every scheduler pass whenever the run queue
is non-empty, independently of the timer.

| binary | RTS opts | result |
|---|---|---|
| `-O` | `-N2` (control) | **not finished after 60 s** |
| `-O` | `-N2 -C0` | max 58 ms, mean 23 ms (3 runs: 58.2 / 58.5 / 56.9 ms) |
| debug | `-N2 -C0` | max 3.7 ms (2 runs) |

With forced context switches the stall disappears, which is what the
front-of-queue explanation predicts.

### RTS variant without `stopTimer()` (`rebuild-nostop.sh`, `nostop.log`)

Three RTS objects swapped into the 9.10.3 archives (same method as
`evidence/rts-fix-check`): `orig` (unmodified recompile), `fixed` (the leak
fix from `mr/`), `nostop` (the leak fix plus the `stopTimer()` /
`startTimer()` pair removed from `setNumCapabilities`, which is what master
did in 341ed474). `caps 50 4 +RTS -N2`, three runs each.

| RTS | `-O` build | debug build |
|---|---|---|
| orig | not finished after 120 s (3/3) | max 4727 / 3580 / 5357 ms; 15 / 9 / 19 of 50 calls over 100 ms |
| fixed (leak fix only) | not finished after 120 s (3/3) | max 3707 / 3067 / 4887 ms; 12 / 12 / 10 over 100 ms |
| nostop (leak fix + no stopTimer) | **max 73 / 75 / 95 ms; 0 over 100 ms** | **max 79 / 73 / 23 ms; 0 over 100 ms** |

Conclusion: the stall is caused by `setNumCapabilities` keeping the RTS
timer stopped while it runs the IO-manager notification as a Haskell
thread; without ticks no context switch is ever forced, so a busy thread
on the caller's capability keeps the notification thread (and therefore
the `setNumCapabilities` call) waiting. The leak fix neither causes nor
cures it. It is present in 9.10.3, 9.12.4 and 9.14.1 and already gone on
master (341ed474, 2026-06-12). `-fno-omit-yields` cannot help; `+RTS -C0`
works around it.

Not measured: whether 9.12 / 9.14 behave the same at run time (only read
in the source), and the 2-CPU container.
