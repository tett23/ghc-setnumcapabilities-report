# verify-a: hypothesis A (setNumCapabilities releases only old_n_capabilities) — results

Program: `scripts/CapRace.hs` (base only). W=4 worker threads allocate and call `performGC`
every 400 iterations; per round, M=4 threads call `setNumCapabilities` concurrently
(`conc`: distinct increasing targets base+1..base+4; `same`: one target; `serial`: same as
conc but under one global MVar; `dec`: raise serially, then concurrent decreases only;
`noop`: start -N8, every call passes 8; `mixed`: increases and decreases together).
After every round the main thread calls `performGC`. A run = one process, 3 rounds
(`e-conc2to16`/`serial2to16`: 1 round, -N2, M=14 -> targets 3..16).

Classification (runmany.sh / runmany-mac.sh): `ok` exit 0 within timeout; `idle_hang` = still
alive after timeout and <0.1 CPU-s consumed over the following 2-3 s; `busy_timeout` = alive
but consuming CPU (slow, not deadlocked). Both machines: GHC 9.10.3, `-O1 -threaded -rtsopts`.

## Container `verify-a-1` (Docker/colima, linux aarch64, --cpus 2, Debian 13, GHC 9.10.3 copied from the golemhang-home volume)

| label | mode | RTS | n | ok | idle_hang | busy_timeout |
|---|---|---|---|---|---|---|
| conc (*) | concurrent increases 1->5, 5->9, 9->13 | -N1 | 200 | 37 | **163 (81.5%)** | 0 |
| conc-dbg | same, `-debug` RTS | -N1 | 50 | 13 | **37 (74%)** | 0 |
| conc-qg (d) | concurrent increases, sequential GC | -N1 -qg | 100 | 34 | **66 (66%)** | 0 |
| same | 4 calls, identical target | -N1 | 100 | 65 | **35 (35%)** | 0 |
| mixed | increases + decreases concurrently | -N1 | 100 | 4 | **23** | 73 |
| serial (a) | increases serialized by MVar | -N1 | 200 | 192 | **0** | 8 |
| dec (b) | concurrent decreases only | -N1 | 200 | 175 | **0** | 25 |
| noopN8 (c) | all calls no-ops | -N8 | 200 | 200 | **0** | 0 |

(*) measured with timeout 8 s while a second, orphaned conc loop (timeout 15 s) was still
running in the same 2-CPU container for part of the time (killed later); the host numbers
below are uncontaminated.

## Host (macOS 27, Apple Silicon, 10 cores, GHC 9.10.3 via ghcup, no CPU limit)

| label | mode | RTS | n | ok | idle_hang | busy_timeout |
|---|---|---|---|---|---|---|
| e-conc2to16 (e) | 14 concurrent increases 2->16 | -N2 | 200 | 2 | **197 (98.5%)** | 1 |
| conc | concurrent increases 1->5, 5->9, 9->13 | -N1 | 200 | 1 | **198 (99%)** | 1 |
| conc-qg (d) | concurrent increases, sequential GC | -N1 -qg | 100 | 3 | **96 (96%)** | 1 |
| same | 4 calls, identical target | -N1 | 100 | 66 | **34 (34%)** | 0 |
| mixed | increases + decreases concurrently | -N1 | 100 | 7 | **68** | 25 |
| serial (a) | increases serialized by MVar | -N1 | 200 | 116 | **0** | 84 |
| serial2to16 | 14 serialized increases 2->16 | -N2 | 200 | 193 | **0** | 7 |
| dec (b) | concurrent decreases only | -N1 | 200 | 151 | **0** | 49 |
| noopN8 (c) | all calls no-ops | -N8 | 200 | 200 | **0** | 0 |
| serial-T60 | serial, 60 s timeout | -N1 | 30 | 28 | 0 | 2 |
| dec-T60 | dec, 60 s timeout | -N1 | 30 | 23 | 0 | 7 |
| serial-noomityields | serial, built with -fno-omit-yields | -N1 | 60 | 42 | 0 | 18 |
| dec-noomityields | dec, -fno-omit-yields | -N1 | 60 | 49 | 0 | 11 |
| conc-noomityields | conc, -fno-omit-yields | -N1 | 30 | 0 | 30 | 0 |

## Dumps

- `gdb/hang1-conc-waitForCapability.gdb.txt` — debug RTS, idle hang: cap 2 `running_task` = Task of the
  `setNumCapabilities(4)` caller whose `task->cap` is cap 0 and whose OS thread is alive, parked in
  `setNumCapabilities -> rts_evalIO -> schedule -> yieldCapability -> waitForWorkerCapability`; the GC
  leader (`performMajorGC`) owns caps 0,1 and blocks in `scheduleDoGC -> waitForCapability`
  (Schedule.c:1789) on cap 2; `setNumCapabilities(5)` blocked in `rts_lock`.
- `gdb/hang3-conc-decreasepath-waitForGcThreads.gdb.txt` (+ `.3s-later`): n_capabilities=9,
  enabled=7; caps 6,7,8 `running_task` = Task of the `setNumCapabilities(7)` caller (decrease path,
  old_n=6); leader holds 0..5 and spins in `waitForGcThreads` (GC.c:1527) because cap 6 looks busy.
  No ownership change in 3 s.
- `trace/conc-Ds-hang.trace.txt` — `+RTS -Ds` of a hang: thread fb950d7af180 logs
  "changing the number of Capabilities from 2 to 4", then "grabbing all the capabilities (0/3) (1/3) (2/3)"
  (n_capabilities had become 3 meanwhile), then releases only caps 1 and 0; cap 2 is never released;
  the next GC logs "asking for cap 2 to be idle" and never completes.
- `gdb/busy-*.gdb.txt`, `lldb/busy-ser.lldb*.txt` — CPU-busy (not idle) stalls: state changes between
  dumps; these are slow GCs / scheduling with many caps, not the leak.
- `gdb/hang2-serial-heavyGC-waitForGcThreads.gdb.txt` — early serial-mode capture with a heavier
  worker (performGC every 7 iterations); GC leader polling in waitForGcThreads, cap 1 free; not
  reproduced as an idle hang in 100 further attempts (60 light + 40 heavy worker).
