# Results: patched Schedule.c swapped into the GHC 9.10.3 RTS archives (macOS 27, 10 cores)

Method: `README.md`. "orig" = the unmodified `Schedule.c` recompiled the same
way (control), "fixed" = with the patch. `ok` = exit 0, `idle_hang` = alive
after the timeout with no CPU use, `other` = non-zero exit (for the test
binaries that is the 60 s watchdog firing).

## Reproducer `CapRace conc 3 4 4 +RTS -N1` (4 concurrent increases per round, 3 rounds, caps 1 -> 13)

| RTS | n | ok | idle_hang | slowest ok run |
|---|---|---|---|---|
| orig | 20 | 0 | **20** | – |
| fixed | 50 | **50** | 0 | 33.1 s (avg 1.08 s) |

## Test candidate `TNNNNN.hs`, rounds=3 setters=4 workers=4 (caps up to base+12)

| build | RTS opts | RTS | n | ok | watchdog (60 s) | slowest ok run |
|---|---|---|---|---|---|---|
| `-O -threaded` (threaded2) | `-N2` | orig | 20 | 0 | **20** | – |
| `-O -threaded` (threaded2) | `-N2` | fixed | 100 | **100** | 0 | 11.2 s (avg 0.39 s) |
| `-threaded -debug` (threaded1) | (-N1) | orig | 10 | 2 | **8** | 60.5 s |
| `-threaded -debug` (threaded1) | (-N1) | fixed | 50 | 49 | **1** | 60.1 s (avg 8.8 s) |

Conclusion so far: the patch removes the hang (0 idle hangs in 200 fixed
runs). But with 13 capabilities on 10 cores the debug RTS sometimes takes
more than 60 s to finish even when fixed (the slow-GC phenomenon noted in
verify-a), so this shape of the test would be flaky in the threaded1 way.
Smaller variants are measured in the next section.

## Smaller variants of the test (`measure2.sh`, `measure2.log`)

rounds×setters as named; workers=4 in all. Unfixed runs use a 20 s watchdog
(so "watchdog" there means > 20 s), fixed runs the 60 s one.

| variant (max caps) | build | RTS | n | ok | watchdog | slowest ok run | avg |
|---|---|---|---|---|---|---|---|
| r2m3 (base+6) | threaded2 `-N2` | orig | 10 | 2 | **8** | 20.4 s | 16.1 s |
| r2m3 | threaded1 | orig | 10 | 1 | **9** | 20.5 s | 19.2 s |
| r2m3 | threaded2 `-N2` | fixed | 60 | **60** | 0 | 8.6 s | 0.40 s |
| r2m3 | threaded1 | fixed | 60 | **60** | 0 | 29.4 s | 2.19 s |
| r3m2 (base+6) | threaded2 `-N2` | orig | 10 | 6 | **4** | 20.3 s | 8.3 s |
| r3m2 | threaded1 | orig | 10 | 10 | 0 | 0.8 s | 0.33 s |
| r3m2 | threaded2 `-N2` | fixed | 60 | **60** | 0 | 3.6 s | 0.54 s |
| r3m2 | threaded1 | fixed | 60 | **60** | 0 | 55.4 s | 1.55 s |
| r1m4 (base+4) | threaded2 `-N2` | orig | 10 | 1 | **9** | 20.4 s | 18.1 s |
| r1m4 | threaded1 | orig | 10 | 5 | **5** | 20.6 s | 10.9 s |
| r1m4 | threaded2 `-N2` | fixed | 60 | **60** | 0 | 23.1 s | 0.54 s |
| r1m4 | threaded1 | fixed | 60 | 57 | **3** | 60.2 s | 8.5 s |

Reading: the fix never deadlocks (0 idle hangs in 360 runs), but the
debug-RTS runs have a heavy tail (up to 55 s with only 7 capabilities on
10 cores, 3/60 over 60 s with 5 capabilities). So the tail is not caused by
the capability count exceeding the core count. The suspect is the GC
pressure: four workers each forcing a major GC every 400 iterations while
the capability count changes. Next: variants without worker GCs
(`measure3.sh`).

## GC-pressure variants, rounds=3 setters=4 (`measure3.sh`, `measure3.log`)

| variant | build | RTS | n | ok | watchdog | slowest ok run | avg |
|---|---|---|---|---|---|---|---|
| w0 (no workers) | threaded2 `-N2` | orig | 10 | 0 | **10** | – | – |
| w0 | threaded1 | orig | 10 | 0 | **10** | – | – |
| w0 | threaded2 `-N2` | fixed | 60 | **60** | 0 | 0.44 s | 0.12 s |
| w0 | threaded1 | fixed | 60 | **60** | 0 | 0.44 s | 0.12 s |
| nogc (workers allocate, never `performGC`) | threaded2 `-N2` | orig | 10 | 0 | **10** | – | – |
| nogc | threaded1 | orig | 10 | 0 | **10** | – | – |
| nogc | threaded2 `-N2` | fixed | 60 | 51 | **9** | 60.1 s | 10.1 s |
| nogc | threaded1 | fixed | 60 | 55 | **5** | 60.2 s | 12.3 s |

Reading: without worker threads the test is both reliable (fails 20/20
unfixed) and fast (120/120 fixed, all under half a second). The slow tail
is caused by the allocating worker threads, and it gets *worse* when they
never call `performGC` (9/60 and 5/60 over 60 s). This is the
"busy_timeout" phenomenon from verify-a, now isolated: a stop-the-world
sync (`setNumCapabilities` or `performGC` from the main thread) takes
seconds to minutes while other threads run tight allocating loops. It is
independent of the leak and is left for a separate investigation.

**Decision:** the testsuite test uses the `w0` shape (rounds=3, setters=4,
no workers). `mr/testsuite/tests/rts/TNNNNN.hs` is that version.

## Same check on Linux (`linux-check.sh`, `linux-check.log`; container `verify-a-1`: Debian 13 aarch64, 2 CPUs, gcc 14.2.0, ghcup GHC 9.10.3)

Final test shape (rounds=3, setters=4, no workers). The control object again
has the same symbol set as the shipped `Schedule.thr_o`; `objdump` counts
177/202 instructions for the control and 197/217 for the fix (thr / thr_debug).

| build | RTS | n | ok | watchdog | slowest ok run |
|---|---|---|---|---|---|
| threaded2 `-N2` | orig | 10 | 3 | **7** | – |
| threaded1 | orig | 10 | 4 | **6** | – |
| threaded2 `-N2` | fixed | 60 | **60** | 0 | 0.12 s |
| threaded1 | fixed | 60 | **60** | 0 | 0.12 s |

Note on reading `runmany.sh` output: its `max_ok_time` / `avg_ok_time`
include the runs that ended by the watchdog's `_exit(1)` (the `other`
column), so for unfixed rows those two numbers just reflect the watchdog
delay and are omitted here. For rows with `other = 0` they are exact.

On 2 CPUs the unfixed test fails in about two thirds of the runs rather
than every time; a six-round variant is measured next (`linux-check2.sh`).

## Six rounds on Linux (`linux-check2.sh`, `linux-check2.log`)

| build | RTS | n | ok | watchdog | idle hang past watchdog | slowest ok run |
|---|---|---|---|---|---|---|
| threaded2 `-N2` | orig | 20 | 0 | **19** | 1 | – |
| threaded1 | orig | 20 | 2 | **18** | 0 | – |
| threaded2 `-N2` | fixed | 60 | **60** | 0 | 0 | 0.13 s |
| threaded1 | fixed | 60 | **60** | 0 | 0 | 0.13 s |

Six rounds make the unfixed test fail 37/40 on 2 CPUs while the fixed run
stays at 0.13 s. One unfixed run hung *past* the 20 s watchdog: the
watchdog was a Haskell thread (`forkIO` + safe foreign call), and it had
evidently not reached its foreign call before the RTS deadlocked, so it
never ran. Fix: start the watchdog as a native thread from C
(`pthread_create` / `CreateThread`) via an unsafe call, which needs no RTS
cooperation. The final files use that, with rounds=6 (`final-check.sh`,
`linux-final.sh`).

## Final test files (`final-check.sh` / `final-mac.log`, `linux-final.sh` / `final-linux.log`)

rounds=6, setters=4, no workers, watchdog on a native thread. Unfixed runs
use a 20 s watchdog, fixed runs the 60 s one from the real file.

| machine | build | RTS | n | ok | watchdog | hung past watchdog | slowest ok run |
|---|---|---|---|---|---|---|---|
| macOS 10 cores | threaded2 `-N2` | orig | 10 | 1 | **9** | 0 | – |
| macOS 10 cores | threaded1 | orig | 10 | 0 | **10** | 0 | – |
| macOS 10 cores | threaded2 `-N2` | fixed | 60 | **60** | 0 | 0 | 0.81 s |
| macOS 10 cores | threaded1 | fixed | 60 | **60** | 0 | 0 | 0.69 s |
| Linux 2 CPUs | threaded2 `-N2` | orig | 20 | 2 | **18** | 0 | – |
| Linux 2 CPUs | threaded1 | orig | 20 | 1 | **19** | 0 | – |
| Linux 2 CPUs | threaded2 `-N2` | fixed | 60 | **60** | 0 | 0 | 0.12 s |
| Linux 2 CPUs | threaded1 | fixed | 60 | **60** | 0 | 0 | 0.12 s |

Summary: unfixed 19/20 (Mac) and 37/40 (Linux) failures; fixed 240/240
passes, slowest 0.81 s; the native watchdog always fired. These are the
numbers quoted in `mr/MR_DESCRIPTION.md` and in the test's header comment.

What this does **not** cover: a hadrian build of master with the patch, the
real testsuite driver (`all.T` entry, ways, Windows), and the `thr_p` /
nonmoving ways. Those remain for tett23 before the MR is opened.

## Hadrian build of GHC master (2026-11-07, macOS, 10 cores)

Checkout: `/Users/tett23/repositories/src/gitlab.haskell.org/ghc/ghc`
(ghq, full clone, tip 20334e1d1f "Avoid panic in
'solveImplicationsUsingUnsatGiven'"), boot GHC 9.14.1 (ghcup), alex /
happy / autoconf / GMP from nixpkgs, `hadrian/build -j10 --flavour=quick
--docs=none` (18m37s for the first build; 10 s to rebuild after the
patch, which recompiles `Schedule.c` for all 8 RTS ways). Result compiler:
`_build/stage1/bin/ghc`, version 10.1.20261106. Test files from `mr/`
copied into `testsuite/tests/rts/` with the `all.T` entry.
Logs: `hadrian-build.log`, `hadrian-test-*.log`, `hadrian-final.log`.

Through the testsuite driver (`hadrian/build test --only=TNNNNN`; at
normal speed the driver runs one way per test, so threaded2 was forced
with `--test-way=threaded2`):

| tree | way | result |
|---|---|---|
| unpatched | threaded1 | **unexpected failure**: bad exit code (1), "TNNNNN: still running after 60 s, giving up" |
| unpatched | threaded2 | **unexpected failure**: same |
| patched | threaded1 | expected pass |
| patched | threaded2 | expected pass |

Looping the test binaries compiled by the patched stage1 compiler
(`-threaded -debug` and `-O -threaded +RTS -N2`): 60 / 60 passes each,
slowest 0.45 s.

State left behind: the checkout has the patch and the test applied as an
uncommitted working-tree change (`git diff --stat`: rts/Schedule.c,
testsuite/tests/rts/all.T, plus the two untracked test files). Nothing
committed, nothing pushed.
