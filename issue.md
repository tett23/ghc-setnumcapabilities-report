<!--
Draft GHC issue. Uses .gitlab/issue_templates/default.md section headings
(Summary / Steps to reproduce / Expected behavior / Environment).
[FILL] markers (if any remain) need tett23's own answer; everything else was
checked against the GHC sources (ghc-9.10.3-release, ghc-9.12.4-release,
ghc-9.14.1-release, master 7dedcf135e) and the runs recorded under
evidence/verify-a (CapRace.hs) and evidence/verify-b.
-->

Title: `setNumCapabilities` leaks capabilities when another `setNumCapabilities` grows the array before it stops the world; the next GC hangs

## Summary

`setNumCapabilities` (rts/Schedule.c) reads `n_capabilities` and
`enabled_capabilities` *before* it stops the world and uses those values
*after* the world has been stopped:

```c
uint32_t old_n_capabilities = n_capabilities;          // Schedule.c:2272 (9.10.3), :2306 (9.14.1), :2281 (master)

if (new_n_capabilities == enabled_capabilities) {      // :2274 / :2308 / :2283
    return;
}
...
cap = rts_lock();
...
stopAllCapabilities(&cap, task);                        // :2297 / :2331 / :2300
...
releaseAllCapabilities(old_n_capabilities, cap,task);  // :2371 / :2405 / :2376
```

`stopAllCapabilities` → `acquireAllCapabilities` acquires
`getNumCapabilities()` capabilities, i.e. as many as exist *when the world
is stopped* (Schedule.c:1543 in 9.10.3). The final `releaseAllCapabilities`
releases only `old_n_capabilities`, as many as existed when the function
was *entered*.

So the condition for the bug is: **the value of `n_capabilities` that a
call reads on entry is smaller than the value of `n_capabilities` at the
moment its `stopAllCapabilities` returns.** That happens whenever another
`setNumCapabilities` call grows the capability array between those two
points. The window is wide, because the second caller usually spends it
blocked in `rts_lock()` or `requestSync()` while the first caller holds all
capabilities. The direction of the second call does not matter: it leaks
capabilities whether it ends up growing, shrinking, or doing nothing.
Capabilities `old_n_capabilities .. n_capabilities-1` are left with
`running_task` pointing at a Task that has returned from
`setNumCapabilities` and no longer knows it owns them.

Two interleavings we have observed with a debug RTS (A and B are two
Haskell threads, each on its own Task):

*Grow/grow.* `n_capabilities == enabled_capabilities == 2`. A calls
`setNumCapabilities 3`, B calls `setNumCapabilities 4`.

1. Both read `old_n_capabilities = 2`; both pass the `new_n == enabled`
   check.
2. A wins the sync, `moreCapabilities(2, 3)`, sets
   `n_capabilities = enabled_capabilities = 3`, releases caps 0..1.
3. B's `stopAllCapabilities` now acquires all **3** capabilities.
4. B grows 3 → 4 (`moreCapabilities(3, 4)`), then
   `releaseAllCapabilities(old_n_capabilities = 2, ...)` releases caps
   0..1 only. Cap 2 keeps `running_task == B` forever.

(`+RTS -Ds` trace of exactly this run: one task logs "changing the number
of Capabilities from 2 to 4", then "grabbing all the capabilities (0/3)
… (2/3)", then "giving up capability 0" / "freeing capability 0" and
nothing for cap 2. The next GC logs "asking for cap 2 to be idle" and
never finishes.)

*Grow/shrink.* `n_capabilities == 6`. B enters `setNumCapabilities 7` and
reads `old_n_capabilities = 6`; before B gets the sync, other calls grow
the array to 9. B's call is now a *shrink* (9 → 7): it disables caps 7..8,
then releases caps 0..5 only. Caps 6..8 keep `running_task == B`; cap 6
is enabled and looks permanently busy.

Nothing notices until the next stop-the-world operation, which then hangs
in one of two places, depending on how the GC classifies the leaked
capability:

* If the leaked capability is treated as idle (the normal case for a
  parallel GC when `enabled_capabilities > n_gc_threads`, and always for a
  sequential GC, `-qg`), the GC leader calls `waitForCapability` on it
  (Schedule.c:1789, or :1554 via `acquireAllCapabilities` for `-qg`). It
  queues itself on the capability's `returning_tasks` and sleeps on a
  condition variable that nobody will signal. The process uses no CPU.
* If the leaked capability is treated as a GC participant, the leader
  loops in `waitForGcThreads` (rts/sm/GC.c:1496; the 1 ms
  `timedWaitCondition` at :1527), prodding the capability every
  millisecond and waiting for a GC thread that can never enter, because no
  Task will ever run on that capability again. The process uses almost no
  CPU.

Every other Task eventually blocks in `yieldCapability` or
`waitForReturnCapability` behind the pending sync. Any later
`setNumCapabilities` or `forkProcess` hangs inside `acquireAllCapabilities`
for the same reason.

gdb on hung processes shows exactly this. A hung grow/grow process
(`n_capabilities = 4`): caps 0..1 have `running_task == A` (A is the GC
leader, in `scheduleDoGC` → `waitForCapability`, Schedule.c:1789), cap 2
has `running_task == B`, A sits on cap 2's `returning_tasks`, and B's OS
thread is alive, parked in `yieldCapability` → `waitForWorkerCapability`
with `task->cap` pointing at cap 0. A hung grow/shrink process (`n_capabilities = 9`,
`enabled_capabilities = 7`): caps 0..5 have `running_task == A` (the GC
leader, in `waitForGcThreads`, GC.c:1527), caps 6..8 have
`running_task == B`, `pending_sync->type == SYNC_GC_PAR`, `idle_cap[6]`
is false, and B is parked in `waitForWorkerCapability`.

The code is the same in `ghc-9.10.3-release`, `ghc-9.12.4-release`,
`ghc-9.14.1-release` and `master` (7dedcf135e, 2026-10-17); the only
differences in `setNumCapabilities` on master are the removed
`stopTimer()/startTimer()` pair, a comment, and the I/O-manager
notification call. I have only run the reproducer with 9.10.3.

How we hit it: tasty 1.5.4 (`Test.Tasty.Parallel.runInParallel`) calls
`setNumCapabilities nthreads` at startup when `getNumCapabilities <
nthreads` (reverted upstream in UnkindPartition/tasty#485, not yet
released), and test cases in our suite called `setNumCapabilities 8`
from several test threads at once. On GitHub Actions `ubuntu-24.04` and
`ubuntu-24.04-arm` runners (2 vCPU each) the test binaries hung in about
2% of the jobs (8 of the last ~400), each time in a test that calls
`setNumCapabilities` while another thread may be doing the same. A
10-core macOS machine never hung in that configuration, but the
standalone reproducer below hangs there almost every time.

Workaround: make sure no two threads can be inside `setNumCapabilities`
at the same time (serialise calls behind an `MVar`), or set the capability
count once from the command line (`-N`, `-with-rtsopts=-N`) and do not
call `setNumCapabilities` at all.

Possibly related tickets; none describes this interleaving: #8209 (an
older `setNumCapabilities` race, fixed in 7.8), #14707 (threads stuck in
`gcWorkerThread` after `setNumCapabilities`), #18808 (TSAN race between
`setNumCapabilities` and `scheduleDoGC` in `setnumcapabilities001`),
#22989 (intermittent timeout of `setnumcapabilities001`; that test has a
single thread calling `setNumCapabilities`, so probably a different cause),
#27460 / #27473 (the `returning_tasks` vs `pending_sync` protocol the hang
goes through), #20144 (a GC-entry deadlock on AArch64/Darwin fixed in 2021,
without `setNumCapabilities`). I also found no merge request touching
this part of `setNumCapabilities`; the only recent changes to it are the
`MAX_N_CAPS` assertion (!13692) and the removal of `stopTimer()` (June
2026).

## Steps to reproduce

Standalone, depends on `base` only. `W` worker threads allocate and call
`performGC` every 400 iterations; per round, `M` threads call
`setNumCapabilities` at the same time; after each round the main thread
calls `performGC`. The mode selects the pattern of calls so that the
control cases can be run with the same binary.

```haskell
{- CapRace: concurrent setNumCapabilities calls.
   Modes (first arg):
     conc    : M threads call setNumCapabilities concurrently with *increasing*
               distinct targets (base+1 .. base+M), per round base grows so that
               n_capabilities really grows (moreCapabilities path).
     same    : like conc, but all M threads use the same target (base+M).
     serial  : like conc, but every setNumCapabilities is wrapped in a global MVar.
     dec     : first (serially) raise to top, then M threads concurrently call
               decreasing targets; never any increase concurrently.
     noop    : all calls use the current enabled count (start with -N8, target 8).
     mixed   : one increase and one decrease concurrently.
   Second arg: rounds. Third arg: M (setter threads). Fourth: worker threads.
   After each round: performGC (this is where the hang happens) and print.
-}
module Main (main) where

import Control.Concurrent
import Control.Exception (evaluate)
import Control.Monad
import Data.IORef
import System.Environment
import System.IO
import System.Mem (performGC)

-- allocation-heavy worker that also calls performGC
worker :: IORef Bool -> IO ()
worker stop = loop (0 :: Int)
  where
    loop i = do
      s <- readIORef stop
      unless s $ do
        let xs = [1 .. (i `mod` 3000) + 100] :: [Int]
        _ <- evaluate (sum xs)
        when (i `mod` 400 == 0) performGC
        loop (i + 1)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  let (mode, rounds, m, w) = case args of
        [a, b, c, d] -> (a, read b, read c, read d)
        _ -> error "usage: CapRace MODE ROUNDS M WORKERS"
  stop <- newIORef False
  replicateM_ w (forkIO (worker stop))
  gate <- newMVar ()
  forM_ [0 .. rounds - 1] $ \r -> do
    n0 <- getNumCapabilities
    let base = case mode of
          "dec" -> 1 + (r + 1) * m -- top of this round
          _ -> n0
    dones <- replicateM m newEmptyMVar
    start <- newEmptyMVar
    case mode of
      "dec" -> do
        -- raise serially first (no concurrency), then decrease concurrently
        setNumCapabilities base
        forM_ (zip [1 .. m] dones) $ \(i, d) -> forkIO $ do
          readMVar start
          setNumCapabilities (base - i)
          putMVar d ()
      "noop" -> forM_ dones $ \d -> forkIO $ do
          readMVar start
          setNumCapabilities n0
          putMVar d ()
      "same" -> forM_ dones $ \d -> forkIO $ do
          readMVar start
          setNumCapabilities (base + m)
          putMVar d ()
      "serial" -> forM_ (zip [1 .. m] dones) $ \(i, d) -> forkIO $ do
          readMVar start
          withMVar gate $ \_ -> setNumCapabilities (base + i)
          putMVar d ()
      "mixed" -> forM_ (zip [1 .. m] dones) $ \(i, d) -> forkIO $ do
          readMVar start
          -- odd threads increase, even threads decrease to 1
          setNumCapabilities (if odd i then base + i else 1)
          putMVar d ()
      _ -> forM_ (zip [1 .. m] dones) $ \(i, d) -> forkIO $ do
          readMVar start
          setNumCapabilities (base + i)
          putMVar d ()
    putMVar start ()
    mapM_ takeMVar dones
    n1 <- getNumCapabilities
    putStrLn ("round " ++ show r ++ " caps " ++ show n0 ++ " -> " ++ show n1 ++ " ; GC...")
    performGC
    putStrLn ("round " ++ show r ++ " GC done")
  writeIORef stop True
  putStrLn "ok"
```

```sh
ghc-9.10.3 -O1 -threaded -rtsopts CapRace.hs -o caprace
# 3 rounds, 4 concurrent setters per round (1->5, 5->9, 9->13), 4 workers
for i in $(seq 1 100); do timeout 10 ./caprace conc 3 4 4 +RTS -N1 || echo "run $i: exit $?"; done
```

A successful run prints `ok` after about 30 ms. A hung run prints nothing
or `round 0 GC done` and then sits with no CPU use until killed
(`timeout` reports exit 124).

Results (GHC 9.10.3, `-O1 -threaded -rtsopts`; "hang" = still alive after
the timeout and consuming no CPU; the few "slow" runs are alive but
consuming CPU and are not this bug):

| mode | RTS | what the setters do | 10-core macOS (aarch64) | 2-CPU Linux container (aarch64) |
|---|---|---|---|---|
| `conc 3 4 4` | `-N1` | 4 concurrent increases per round, distinct targets | **198 / 200 hang** | **163 / 200 hang** |
| `conc 1 14 4` | `-N2` | 14 concurrent increases 2 → 16 | **197 / 200 hang** | – |
| `conc 3 4 4` | `-N1 -qg` | same, sequential GC | **96 / 100 hang** | **66 / 100 hang** |
| `same 3 4 4` | `-N1` | 4 concurrent calls with the *same* target | **34 / 100 hang** | **35 / 100 hang** |
| `mixed 3 4 4` | `-N1` | increases and decreases concurrently | **68 / 100 hang** | **23 / 100 hang** |
| `serial 3 4 4` | `-N1` | same targets as `conc`, calls serialised by an `MVar` | 0 / 200 hang | 0 / 200 hang |
| `dec 3 4 4` | `-N1` | raise serially, then concurrent *decreases* only | 0 / 200 hang | 0 / 200 hang |
| `noop 3 4 4` | `-N8` | every call is a no-op (8 → 8) | 0 / 200 hang | 0 / 200 hang |

The three controls match the mechanism: serialised calls never hang,
concurrent calls that cannot grow the array never hang, and no-op calls
never hang. Building with `-fno-omit-yields` changes nothing (30 / 30
hang in `conc` mode). A `-debug` RTS hangs at the same rate.

Unrelated to the leak, but visible in the same runs: with allocating
worker threads, some *serialised* `setNumCapabilities` calls take seconds
to minutes while using CPU (84 / 200 `serial` runs on the 10-core machine
exceeded a 4 s timeout). I traced this separately: `setNumCapabilities`
calls `stopTimer()` before the sync and `startTimer()` only after
`rts_evalIO(ioManagerCapabilitiesChanged_closure)` (Schedule.c:2295,
:2378, :2382 in 9.10.3; the same order in 9.12.4 and 9.14.1). With no
timer ticks, `scheduleHandleYield` re-queues a yielding thread at the
*front* of the run queue every time, so the bound thread that runs the
IO-manager notification can be starved by one busy thread on the same
capability; `+RTS -Ds` shows it runnable for 2.5 s while a worker thread
is re-run after 300 stops. `+RTS -C0` removes the stall, and so does
removing the `stopTimer()`/`startTimer()` pair, which master already did
in 341ed474 ("Remove redundant use of stopTimer in setNumCapabilities",
2026-06-12). This is a separate problem from the leak and does not need
the fix above; I mention it so that slow runs are not mistaken for this
bug, and because 341ed474 may be worth backporting.

To see the mechanism, build with `-debug` and run with `+RTS -N1 -Ds`:
one task logs "changing the number of Capabilities from N to M", then
"grabbing all the capabilities (0/K) … (K-1/K)" with `K > N`, and then
releases only caps `0..N-1`; the next GC logs "asking for cap N to be
idle" and never completes. Attaching gdb to a hung process and printing
`n_capabilities`, `enabled_capabilities`, `*pending_sync`, and
`capabilities[i]->running_task` / `->returning_tasks_hd` for each `i`
shows the capabilities `old_n .. n_capabilities-1` owned by a Task whose
thread is parked in `waitForWorkerCapability`.

## Expected behavior

Concurrent `setNumCapabilities` calls should be safe: the function already
goes through `requestSync`/`stopAllCapabilities` so that only one of them
runs at a time, and the documentation of `setNumCapabilities` does not
ask callers to serialise. The program above should exit 0 in every run and
in every mode. Instead, whenever one call grows the capability array while
another call is on its way into `stopAllCapabilities`, the second call
leaks capabilities and the next GC hangs forever.

A fix would read `n_capabilities` / `enabled_capabilities` *after*
`stopAllCapabilities` has returned (re-doing the
`new_n_capabilities == enabled_capabilities` check there and releasing
what was acquired before returning early), so that
`releaseAllCapabilities` is always given the number that
`acquireAllCapabilities` acquired. I can prepare an MR with a testsuite
test if that is welcome.

## Environment

* GHC version used: 9.10.3 (`ghc-9.10.3-release`, ghcup binaries). The relevant code is unchanged in 9.12.4, 9.14.1 and master (7dedcf135e, 2026-10-17); the reproducer was not run with those.

Optional:

* Operating System: macOS 27.0 (Darwin 27.0.0, 10-core Apple Silicon); Debian GNU/Linux 13 (trixie) aarch64 in a 2-CPU Docker container (Linux 6.8); GitHub Actions `ubuntu-24.04` (x86-64) and `ubuntu-24.04-arm` runners, 2 vCPU each, for the original symptom
* System Architecture: aarch64 (macOS, Linux container, arm CI runner) and x86-64 (CI runner)
* Build: `-O1 -threaded -rtsopts`; also with `-debug` for the `-Ds` trace and gdb
* C compiler: Apple clang 21.0.0 (clang-2100.3.34.2) on macOS; gcc (Debian 14.2.0-19) 14.2.0 in the container
* Downstream trigger: tasty 1.5.4 (`Test.Tasty.Parallel` calls `setNumCapabilities` when the thread count exceeds the capability count) plus application code calling `setNumCapabilities 8` from several threads.

LLM assistance: Claude Code (Anthropic) was
used while analysing the RTS source, writing the reproducer and the
debugging scripts, and drafting this report
(https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI, P4). I have
read and revised the text and the reproducer, run the reproducer myself,
and take responsibility for them.

/label ~"T::bug"
/label ~"needs triage"
<!-- Triagers add ~RTS ~concurrency and a priority; suggest them in a comment if you cannot set labels. -->
