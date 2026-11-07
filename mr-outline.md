# Merge request outline (post the issue first; replace NNNNN with its number)

GHC's rules (wiki "working-conventions/fixing-bugs", MR template
`.gitlab/merge_request_templates/Default.md`): every MR points to a ticket;
test named after the ticket; commit message describes the change and
references `#NNNNN`; `changelog.d/` entry or the ~"no-changelog" label;
source comment/Note at the fix site; squashed, bisectable commits;
`Assisted-By:` trailer plus a declaration in the MR description if an LLM
generated any part.

## 1. The patch (rts/Schedule.c, `setNumCapabilities`)

Root cause: the counts read before `stopAllCapabilities` are stale once the
world is stopped. Fix: take the snapshots *after* the world is stopped, and
release exactly what `acquireAllCapabilities` acquired.

Option A (recommended, minimal, no new locking):

```c
    Task *task;
    Capability *cap;
    uint32_t n;
    Capability *old_capabilities = NULL;
    uint32_t old_n_capabilities;

    // Preliminary checks on a snapshot. These are re-done below once the
    // world is stopped; see Note [setNumCapabilities is not atomic].
    if (new_n_capabilities == enabled_capabilities) {
        return;
    } else if (new_n_capabilities <= 0) {
        errorBelch("setNumCapabilities: Capability count must be positive");
        return;
    } else if (new_n_capabilities > max_n_capabilities) {
        // See Note [Capabilities array sizing] in rts/Capability.c.
        errorBelch("setNumCapabilities: Attempt to increase capability count beyond maximum capability count %" PRIu32 "; clamping...\n", max_n_capabilities);
        new_n_capabilities = max_n_capabilities;
    }

    cap = rts_lock();
    task = cap->running_task;

    stopTimer();                 // 9.10 only; master no longer has this

    stopAllCapabilities(&cap, task);

    // We now own every capability. Only now are n_capabilities and
    // enabled_capabilities stable: another setNumCapabilities may have
    // run between our snapshot above and stopAllCapabilities().
    // acquireAllCapabilities() took n_capabilities capabilities, and
    // that is exactly what we must give back below.
    old_n_capabilities = n_capabilities;

    if (new_n_capabilities == enabled_capabilities) {
        // Somebody else already did it. Release what we hold and leave.
        releaseAllCapabilities(old_n_capabilities, cap, task);
        startTimer();            // 9.10 only
        rts_unlock(cap);
        return;
    }

    debugTrace(DEBUG_sched, "changing the number of Capabilities from %d to %d",
               enabled_capabilities, new_n_capabilities);

    ... unchanged shrink / grow code ...

    releaseAllCapabilities(old_n_capabilities, cap,task);
```

Points to double-check while writing the real patch:

* `old_n_capabilities` must be the value of `n_capabilities` *before*
  `moreCapabilities` runs in the grow branch (it is; the assignment moves
  to just after `stopAllCapabilities`).
* The early return after `stopAllCapabilities` must undo everything that
  was done before it: `releaseAllCapabilities`, `startTimer()` (9.10.x
  branch only; master removed the timer stop), `rts_unlock`. The
  `ioManagerCapabilitiesChanged` notification is not needed because nothing
  changed.
* `stopAllCapabilitiesWith` already clears `pending_sync`, so the early
  return does not need to touch it.
* Consider a `Note [setNumCapabilities is not atomic]` (or a shorter inline
  comment) that states the invariant: "releaseAllCapabilities(n) must
  receive the capability count that acquireAllCapabilities saw", and
  references `#NNNNN`. GHC's AI policy asks that Notes be written by the
  human author.
* Optional hardening: have `stopAllCapabilities` return the number of
  capabilities it acquired (or have `releaseAllCapabilities` take no count
  and use `n_capabilities`), so the invariant cannot be broken again. That
  changes two other call sites (`forkProcess`, `scheduleDoGC`); keep it out
  of the bug-fix MR unless a reviewer asks.

Option B (alternative): guard `setNumCapabilities` with a dedicated mutex
so calls are fully serialised. Rejected as the primary proposal: it adds a
lock that must be ordered against `rts_lock`/`requestSync`, it does not
make the stale-snapshot code correct (it only hides it), and the sync
protocol is already meant to serialise these operations.

## 2. Commit message (GHC style, one squashed commit)

```
rts: Fix capability leak in concurrent setNumCapabilities calls

setNumCapabilities read n_capabilities and enabled_capabilities before
stopAllCapabilities() and used the stale values afterwards.  If another
setNumCapabilities call grew the capability array in between, the
second call acquired all n_capabilities capabilities in
acquireAllCapabilities() but released only the old count in
releaseAllCapabilities(), leaving the new capabilities with a dangling
running_task.  The next stop-the-world sync (typically a parallel GC
with idle capabilities) then waited forever for those capabilities.

Take the snapshot after the world has been stopped, re-check whether
there is anything left to do, and release exactly the capabilities that
were acquired.

Fixes #NNNNN

Assisted-By: <tool>      # only if an LLM generated part of the material
```

(Wiki: subject line + blank line + body; reference the ticket as `#NNNNN`;
a line starting with `Closes #NNNNN` auto-closes the ticket, `Fixes` does
not and is the commoner form in GHC history. Pick one.)

## 3. Testsuite test (testsuite/tests/rts/)

Name after the ticket (`TNNNNN`). The race is probabilistic, so the test
runs six rounds of four concurrent increases inside one process and forces
a GC after each round; with the bug it hangs, with the fix it prints
nothing and exits 0. A watchdog on a native thread (created from C with
`pthread_create`/`CreateThread`, so it needs no RTS cooperation) turns a
hang into a clean failure instead of a 300 s testsuite timeout.

Measured 2026-10-17/18 with the patched `Schedule.c` swapped into the
9.10.3 RTS archives (`evidence/rts-fix-check/RESULTS.md`): unfixed fails
19/20 on a 10-core Mac and 37/40 in a 2-CPU Linux container (threaded1 and
threaded2 together); fixed passes 120/120 on each machine, slowest run
0.81 s. Allocating worker threads were removed from the test on purpose:
they made fixed runs take up to a minute (a separate RTS behaviour, see
`LOG.md`), which would have made the test fragile. The final files are
under `mr/testsuite/tests/rts/`; the listing below is the earlier sketch
and is superseded by them.

`testsuite/tests/rts/TNNNNN.hs`:

```haskell
-- Concurrent setNumCapabilities calls must not leak capabilities (#NNNNN).
-- Several threads request the same, larger, capability count at once;
-- with the bug the next GC (or the next setNumCapabilities) deadlocks.
{-# LANGUAGE ForeignFunctionInterface #-}
import Control.Concurrent
import Control.Monad
import Foreign.C.Types
import System.Mem (performGC)

foreign import ccall safe "watchdog" c_watchdog :: CInt -> IO ()

main :: IO ()
main = do
  _ <- forkOS (c_watchdog 60)          -- _exit(1) after 60 s if we hang
  start <- getNumCapabilities          -- +RTS -N2
  forM_ [start + 1 .. 24] $ \target -> do
    go <- newEmptyMVar
    dones <- forM [0 .. start - 1] $ \c -> do
      done <- newEmptyMVar
      _ <- forkOn c $ readMVar go >> setNumCapabilities target >> putMVar done ()
      pure done
    putMVar go ()
    mapM_ takeMVar dones
    performGC
```

`testsuite/tests/rts/TNNNNN_c.c`:

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

void watchdog(int seconds)
{
    sleep(seconds);
    fprintf(stderr, "TNNNNN: deadlock, giving up\n");
    _exit(1);
}
```

`testsuite/tests/rts/all.T` entry (same shape as `T22012`, which also
passes a C file to `compile_and_run`, and `setnumcapabilities001` in
`testsuite/tests/concurrent/should_run/all.T` for the SMP requirements):

```python
# Concurrent setNumCapabilities calls leaked capabilities (#NNNNN)
test('TNNNNN',
     [ only_ways(['threaded1', 'threaded2']),
       req_target_smp,
       req_ghc_smp,
       extra_run_opts('+RTS -N2 -qn2 -A1m -RTS') ],
     compile_and_run,
     ['TNNNNN_c.c'])
```

Notes: `-qn2` fixes the parallel-GC thread count so `need_idle > 0` on any
core count; `-A1m` bounds nursery memory as caps grow to 24; no `.stdout`
file because the program prints nothing on success. If the testsuite's
Windows runners dislike `sleep`/`_exit`, add `when(opsys('mingw32'), skip)`
or use `Sleep`/`ExitProcess` under `#if defined(_WIN32)`.

## 4. changelog.d entry

File `changelog.d/NNNNN` (field syntax per wiki "contributing/changelog";
`section` must be a key from `changelog.d/config`, here `rts`):

```
section: rts
synopsis: Fix a deadlock when several threads call ``setNumCapabilities``
  concurrently
description: {
  ``setNumCapabilities`` released only the capabilities that existed when
  it was called, not those it had acquired after stopping the world.  When
  two threads increased the capability count at the same time, the
  capabilities added by the first call were left permanently owned by the
  second caller's task, and the next garbage collection (or any later
  stop-the-world operation) waited for them forever.
}
issues: #NNNNN
mrs: !MMMMM
```

(`mrs` can only be filled in after the MR exists; GHC's CI checks the
file, so push the number in a follow-up commit or amend before un-drafting.)

## 5. MR description skeleton (replace the template text; do not leave it unchanged)

```
Fixes #NNNNN.

`setNumCapabilities` snapshotted `n_capabilities`/`enabled_capabilities`
before `stopAllCapabilities()` and used the stale values to decide how many
capabilities to release. A concurrent call that grew the array made the
second caller leak the new capabilities (dangling `running_task`), and the
next GC sync hung. This MR moves the snapshot after the world stop,
re-checks whether there is anything left to do, and releases exactly the
capabilities acquired.

Where to look: `rts/Schedule.c`, `setNumCapabilities`, the block right
after `stopAllCapabilities`. Test: `testsuite/tests/rts/TNNNNN`.

LLM assistance: <tool> was used for <analysis/drafting/...>. I have
reviewed and revised every line and take full responsibility for it (P3).

- [x] This MR solves the problem described in #NNNNN
- [x] Changelog entry added in `changelog.d/NNNNN`
- [x] Testcase added: `testsuite/tests/rts/TNNNNN`
- [x] Commit message describes what it does, referring to #NNNNN
```

Labels to ask for in a comment (contributors without extra rights usually
cannot set them): ~RTS ~concurrency, and after merge ~"backport needed:9.14"
/ ~"backport needed:10.0" or whatever the currently maintained release
branches are (check the open milestones; 9.10.x may be out of support).
