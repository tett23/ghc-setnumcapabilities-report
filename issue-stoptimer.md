<!--
Draft for a second GHC issue (file after the capability-leak issue; replace
#NNNNN with that issue's number). Same template as issue.md. Everything
below was measured on GHC 9.10.3 (macOS, 10 cores) except where it says
"read in the source". Evidence: evidence/sync-lag/.
-->

Title: `setNumCapabilities` can stall for seconds or longer because it keeps the timer stopped while running the I/O-manager notification (fixed on master by 341ed474; backport?)

## Summary

In every released GHC I looked at (9.10.3, 9.12.4, 9.14.1) `setNumCapabilities`
(rts/Schedule.c) calls `stopTimer()` before it stops the world and
`startTimer()` only after the I/O-manager notification at the end:

```c
    stopTimer();                                                  // Schedule.c:2295 (9.10.3)
    stopAllCapabilities(&cap, task);
    ...
    releaseAllCapabilities(old_n_capabilities, cap,task);
    ...
    rts_evalIO(&cap, ioManagerCapabilitiesChanged_closure, NULL); // :2378
    startTimer();                                                 // :2382
    rts_unlock(cap);
```

(9.12.4 and 9.14.1 have the same order with `notifyIOManagerCapabilitiesChanged(&cap)`
in place of the `rts_evalIO`; read in the source, not run.)

The notification runs Haskell code (`ioManagerCapabilitiesChanged`) as a
bound thread on the caller's capability. While the timer is stopped there
are no ticks, so `cap->context_switch` is never set, and
`scheduleHandleYield` (Schedule.c:1252) and `scheduleHandleHeapOverflow`
(:1142) put a thread that stops back at the *front* of the run queue
every time. If another runnable thread sits on the same capability, it is
re-run after each of its stops and the bound notification thread never
gets a turn. `setNumCapabilities` does not return until that thread has
finished, so the caller stalls: for seconds in a debug build, where GC
interrupts occasionally break the pattern, and until the busy thread
blocks in an optimised build where the busy thread allocates little.

Observed with the reproducer below (4 allocating threads, the main thread
calls `setNumCapabilities` 50 times, alternating n+1 and n, `+RTS -N2`):

| build | RTS options | 50 calls |
|---|---|---|
| `-O -threaded` | `-N2` | **not finished after 120 s** (6 of 6 runs) |
| `-O -threaded` | `-N2 -C0` | max 58 ms per call (3 runs) |
| `-threaded -debug` | `-N2` | max 0.1–5.4 s per call, up to 19 of 50 calls over 100 ms (11 runs) |
| `-threaded -debug` | `-N2 -C0` | max 3.7 ms (2 runs) |
| `-O -threaded`, RTS with the `stopTimer()`/`startTimer()` pair removed | `-N2` | max 95 ms (3 runs) |
| `-threaded -debug`, same RTS | `-N2` | max 79 ms (3 runs) |

`performGC` from the same main thread under the same load takes about
1 ms every time, so this is specific to `setNumCapabilities`.

A `+RTS -Ds` trace of a 2.5 s call in the debug build shows the sequence:
"changing the number of Capabilities from 2 to 3" at t=55.7 ms, the sync
and the new capability done by 55.8 ms, "cap 1: created thread 10 / new
bound thread (10)" at 56.1 ms (the notification thread), the bound task
handing capability 1 to a worker at 56.4 ms because an unbound thread was
at the head of the run queue, and then that worker re-running its thread
after every one of more than 300 "stopped (yielding)" / "stopped (heap
overflow)" events until 2557 ms, while every "all threads" dump lists
thread 10 as "not blocked" on capability 1. At 2557.1 ms "passing
capability 1 to bound task", thread 10 runs and finishes immediately.

The timer stop was there for #17289 (ticks touching a capability array
that was being reallocated). Since the array is no longer reallocated,
master removed the pair on 2026-06-12 in 341ed474 ("Remove redundant use
of stopTimer in setNumCapabilities", noted there as a partial fix of
#27105). I have not run master; the last row of the table is 9.10.3's
`rts/Schedule.c` with the same two lines removed, compiled and swapped
into the 9.10.3 RTS archives.

I ran into this while investigating #NNNNN (capabilities leaked by
concurrent `setNumCapabilities` calls); the two are independent, and the
fix for #NNNNN does not change this behaviour. Possibly related:
#27105 (`stopTimer` is asynchronous), #27473 (GC sync promptness).

## Steps to reproduce

Standalone, depends on `base` only:

```haskell
{- SyncLag: how long does a stop-the-world operation take while other threads
   allocate?  usage: synclag MODE ITERS WORKERS [+RTS ...]
     MODE  gc    : main calls performGC ITERS times
           caps  : main calls setNumCapabilities alternately n+1 / n, ITERS times
   Workers allocate (a list of up to 3100 Ints per iteration) and never
   call performGC.  Prints the max / mean latency per operation and how many
   operations took more than 100 ms. -}
module Main (main) where

import Control.Concurrent
import Control.Exception (evaluate)
import Control.Monad
import Data.IORef
import GHC.Clock (getMonotonicTimeNSec)
import System.Environment
import System.IO
import System.Mem (performGC)
import Text.Printf (printf)

worker :: IORef Bool -> IO ()
worker stop = loop (0 :: Int)
  where
    loop i = do
      s <- readIORef stop
      unless s $ do
        let xs = [1 .. (i `mod` 3000) + 100] :: [Int]
        _ <- evaluate (sum xs)
        loop (i + 1)

timed :: IO () -> IO Double
timed act = do
  t0 <- getMonotonicTimeNSec
  act
  t1 <- getMonotonicTimeNSec
  pure (fromIntegral (t1 - t0) / 1e6)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  [mode, itersS, workersS] <- getArgs
  let iters = read itersS :: Int
      workers = read workersS :: Int
  stop <- newIORef False
  replicateM_ workers (forkIO (worker stop))
  threadDelay 20000
  n0 <- getNumCapabilities
  lats <- forM [1 .. iters] $ \i -> do
    let target = if odd i then n0 + 1 else n0
    case mode of
      "gc" -> timed performGC
      "caps" -> timed (setNumCapabilities target)
      _ -> error "mode: gc | caps"
  writeIORef stop True
  let mx = maximum lats
      mean = sum lats / fromIntegral (length lats)
      slow = length (filter (> 100) lats)
  printf "mode=%s iters=%d workers=%d caps=%d max_ms=%.1f mean_ms=%.2f over100ms=%d\n" mode iters workers n0 mx mean slow
```

```sh
ghc-9.10.3 -O -threaded -rtsopts SyncLag.hs -o synclag
./synclag gc 50 4 +RTS -N2        # finishes at once, max_ms about 1.5
./synclag caps 50 4 +RTS -N2      # does not finish (kill it after a minute or two)
./synclag caps 50 4 +RTS -N2 -C0  # finishes, max_ms about 60
```

With `-threaded -debug` instead of `-O -threaded`, the `caps` run finishes
but individual calls take up to several seconds; `+RTS -Ds` shows the
starved bound thread as described above.

The reproducer, the measurement logs and the `-Ds` trace are in
https://github.com/tett23/ghc-setnumcapabilities-report
(`evidence/sync-lag/`).

## Expected behavior

`setNumCapabilities` should return in a bounded time once the sync is
done; it should not depend on the other threads on its capability happening
to block. With the `stopTimer()`/`startTimer()` pair removed (as on master)
every call in the runs above completed within 95 ms.

If 341ed474 can be backported to the maintained release branches, that
would resolve this for released compilers.

## Environment

* GHC version used: 9.10.3 (ghcup binaries). The same code order is in `ghc-9.12.4-release` and `ghc-9.14.1-release` (read, not run); master (7dedcf135e and later) no longer has the `stopTimer()`.

Optional:

* Operating System: macOS 27.0 (Darwin 27.0.0)
* System Architecture: aarch64 (10-core Apple Silicon)
* Build: `-O -threaded -rtsopts` and `-threaded -debug -rtsopts`
* C compiler: Apple clang 21.0.0 (clang-2100.3.34.2) (used to recompile `rts/Schedule.c` for the "pair removed" rows)

LLM assistance: Claude Code (Anthropic) was used while analysing the RTS
source, writing the reproducer and the scripts, and drafting this report
(https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI, P4). I have
read and revised the text and the reproducer, run the reproducer myself,
and take responsibility for them.

/label ~"T::bug"
/label ~"needs triage"
<!-- Triagers add ~RTS and a priority; mention ~"backport needed:9.14" (or the current maintained branches) in a comment. -->
