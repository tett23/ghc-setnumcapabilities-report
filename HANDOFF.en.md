# Hand-over: investigating and reporting the GHC `setNumCapabilities` race

English translation of `HANDOFF.md` (the Japanese original is the one the
investigating sessions read; this translation was made on 2026-11-10 for
readers of the published repository). The document is a snapshot of the
state at the hand-over on 2026-10-17, with later edits to the file map; it
is not updated with the results. For those see `LOG.md`, `issue.md`,
`issue-stoptimer.md` and `evidence/`.

What was found in the Golem (tett23/golem) session on 2026-10-17 is handed
over here to the session that continues the investigation and the report in
this folder. Read this file first, then the files in the order of "File map"
below.

## Goal

Report an RTS bug to GHC upstream (gitlab.haskell.org/ghc/ghc). File the
issue first; if a fix is submitted too, open a merge request that refers to
the issue afterwards (GHC's convention; see `maintainer-checklist.md`).
Posting, account creation and pushing the MR are done by tett23 personally.
This session's job is to pin down the cause, finish the issue and MR drafts,
and investigate the open questions.

## What is known

### Symptom

- Golem's tests (GHC 9.10.3, tasty 1.5.4, `-threaded`) sometimes hung
  forever on Linux with few CPUs (GitHub Actions `ubuntu-24.04` on x86-64
  and arm, Docker with 2 CPUs).
- On a 10-core macOS machine the tests in their original form did not hang
  (the minimal reproducer does hang on macOS as well).
- When hung, every OS thread was waiting inside the RTS (the GC leader in
  `scheduleDoGC` → `waitForCapability`, the others in `yieldCapability` or
  `resumeThread` → `waitForReturnCapability`).

### Cause (confirmed)

`setNumCapabilities` in `rts/Schedule.c` (ghc-9.10.3-release; the same order
in 9.12.4, 9.14 and master 7dedcf135):

- Reading `old_n_capabilities = n_capabilities` (line 2272) and the
  `new_n_capabilities == enabled_capabilities` check (line 2274) come before
  `stopAllCapabilities` (line 2297).
- After the sync, `acquireAllCapabilities` takes every capability that
  exists at that moment (line 1543).
- The final `releaseAllCapabilities(old_n_capabilities, …)` (line 2371)
  releases only the old number.
- So when two calls overlap and the `old_n` the later call read is smaller
  than `n_capabilities` at the time of its sync, the capabilities in between
  keep `running_task` pointing at the later call's Task.
- The next GC waits for those capabilities forever.
  - If a leaked capability counts as idle, the GC blocks in
    `waitForCapability` (lines 1786–1789).
  - If it counts as busy, the 1 ms polling loop in `waitForGcThreads`
    (GC.c:1527) never finishes (almost no CPU is used).

### Evidence (`evidence/`)

- **verify-a** (minimal reproducer `CapRace.hs`, `base` only): the tables are
  in `evidence/verify-a/RESULTS.md`.
  - On the 10-core Mac, concurrent increases hang 198/200. Fourteen threads
    growing 2→16 at once hang 197/200. With `-qg`, 96/100 still hang.
  - Controls: serialised through an MVar 0/200; decreases only 0/200; with
    `-N8` and no-op calls 200/200 finish normally.
  - With the debug RTS, gdb and `+RTS -Ds` show directly which Task owns the
    leaked capability and which capabilities are never released (`gdb/`,
    `trace/`).
- **verify-b** (`SetCapsRace.hs`): in a 2-CPU container, 5 hangs out of 179
  runs. gdb dumps and `-Ds` traces included. In the last 400 CI runs, the
  only tests that hung were the four that call `setNumCapabilities` while
  running (`ci-orphan-processes-per-run.txt`).
- **plugin-test-repro** (`Race.hs`): hangs 10/32 on 4-CPU Linux, 9/15 on
  macOS. With a single call, 0 of about 810.
- **tasty-pure-repro**: a tasty test without any Golem code hangs 26/149.
- **rts-9.10.3-source**: copy of the RTS sources as read (removed on
  2026-11-08; refer to the tag `ghc-9.10.3-release`).

### Golem-side fix (done)

tett23/golem#174 links the tests with `-with-rtsopts=-N` and removes
`setNumCapabilities` from the tests. `scripts/ci/rts-capabilities.sh` guards
against regressions. Golem's CI has not hung since.

## Still to decide (handled in this session)

1. **Finish the issue draft** (`issue.md`)
   - Fill the `[VERIFY]` numbers from the verify-a and verify-b results above.
   - `[FILL]` items are facts about tett23's environment (OS, C compiler
     version and so on); ask tett23.
   - Restate the condition precisely. Wider than "two growing calls
     overlap": "the `old_n` the later call read is smaller than
     `n_capabilities` at its sync" covers both directions (verify-a's hang3
     is a shrinking example).
   - Say that there are two hang sites (`waitForCapability` and
     `waitForGcThreads`).
   - Keep the line declaring LLM use (required by GHC's AI policy).
2. **A phenomenon verify-a could not explain**
   - Even with serialised calls, or decreases only, when the number of
     capabilities (up to 13) exceeds the number of cores (2–10), some runs
     keep using CPU for seconds to over 60 s without finishing
     (`busy_timeout`).
   - `-fno-omit-yields` does not remove it. In gdb the process is in the
     middle of GC (scavenge) or in the `waitForGcThreads` polling loop, and
     the state changes with every dump. One case finished normally 3 s
     later.
   - Believed to be slow rather than deadlocked, but the cause is unknown.
     Decide whether to include it in the issue or treat it separately.
     (Resolved on 2026-11-06: it is the `stopTimer()` starvation described in
     `issue-stoptimer.md`.)
3. **Whether to open an MR** (`mr-outline.md`)
   - The fix: move the read of `old_n_capabilities` and the early-return
     check after `stopAllCapabilities`.
   - If so, GHC must be built with hadrian and a test
     (`testsuite/tests/rts/T<number>`) prepared that fails before the fix
     and passes reliably after it.
   - The MR is the responsibility of a human who understands and can explain
     every line (GHC's AI policy).
4. **Duplicate check**
   - gitlab.haskell.org's web UI is blocked by Anubis, so use the REST API
     (`https://gitlab.haskell.org/api/v4/projects/ghc%2Fghc/issues?search=...`)
     or the GitHub mirror.
   - Nearby tickets: [#22989](https://gitlab.haskell.org/ghc/ghc/-/issues/22989),
     [#18808](https://gitlab.haskell.org/ghc/ghc/-/issues/18808),
     [#27460](https://gitlab.haskell.org/ghc/ghc/-/issues/27460),
     [#27473](https://gitlab.haskell.org/ghc/ghc/-/issues/27473). None
     describes this race.
5. **Telling tasty**: the start-up `setNumCapabilities` entered tasty in
   1.5.4 (UnkindPartition/tasty#457) and was reverted in #485 (unreleased at
   the time). Decide whether tasty needs to be told.

## File map

- `README.md`: the entry point for the published repository (English).
  Repository: https://github.com/tett23/ghc-setnumcapabilities-report
  (published 2026-11-08). `publish-checklist.md`: what tett23 decides and
  fixes before publishing (2026-11-08).
- `tasty-comment.md`: draft of an optional comment on tasty#485 (the
  conclusion on item 5 is in `notes-sources.md`).
- `issue-stoptimer.md`: English draft of the separate issue for the stall
  (item 2). Backport request for 341ed474. Evidence in `evidence/sync-lag/`.
- `LOG.md`: chronological record of the investigation (English; added after
  the hand-over on 2026-10-17: what was tried, failures, measurements,
  reasons for decisions).
- `mr/`: what goes into the MR (patch, test, changelog, commit message, MR
  description).
- `evidence/rts-fix-check/`: how the fix was verified without building GHC,
  and the results.
- `issue.md`: English draft of the issue (GHC's default template).
- `mr-outline.md`: MR approach, commit message, test ideas, changelog format.
- `maintainer-checklist.md`: what tett23 does personally (account, posting,
  MR).
- `notes-sources.md`: URLs read, duplicate-search results, reasons for
  decisions.
- `raw/`: removed on 2026-11-08 while preparing for publication (GitLab API
  JSON and copies of GHC documents; `notes-sources.md` lists what was read).
- `evidence/verify-a/`, `evidence/verify-b/`, `evidence/plugin-test-repro/`,
  `evidence/tasty-pure-repro/`: the "Evidence" above.
  `evidence/rts-9.10.3-source/`, `evidence/plugin-fix.diff`,
  `verify-b/proposed-fix-applied-in-scratch.diff` (Golem diffs) and `repro/`
  were removed on 2026-11-08.

## Environment

- **Docker (colima)**: kept at tett23's request. Do not delete.
  - Profile `default` (aarch64, 2 CPUs, 2 GiB)
    - container `verify-a-1` (2 CPUs, binaries and logs in `/root/build`),
      volume `verify-a-home`
    - container `verify-b-1`, volume `verify-b-home`
    - container `golemhang-a892`, volume `golemhang-a892-home`
    - image `golemhang-img` (Debian, GHC 9.10.3 from ghcup, cabal 3.16.1.0,
      gdb), volume `golemhang-home`
  - Profile `golemplug` (aarch64, 4 CPUs, 8 GiB)
    - container `plughang` (debug binaries in `/w2`, fixed build in
      `/t/plugin-fixed`)
  - Memory is tight, so building a large project like Golem may fail; the
    minimal reproducers are fine.
- **Cloned repositories** (ghq, read only)
  - GHC: `/Users/tett23/repositories/src/github.com/ghc/ghc` (partial clone
    with only the needed files; ghc-9.10.3-release and master 7dedcf135)
  - tasty: `/Users/tett23/repositories/src/github.com/UnkindPartition/tasty`
  - The official upstreams may be cloned with ghq when needed (approved by
    tett23).
- **Mac**: 10 cores, GHC 9.10.3 from ghcup, lldb.

## Rules

- Output to tett23 in Japanese; text for GHC in English.
- No posting, no account creation, no pushing of the MR (tett23 does those).
- Downloads only from official upstreams (GHC, tasty, official Docker images,
  ghcup).
- The Golem repository is not modified in this investigation.
