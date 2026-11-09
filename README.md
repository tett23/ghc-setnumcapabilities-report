# GHC `setNumCapabilities` race: report and evidence

Supporting material for two GHC issues and one merge request:

| What | File | Upstream |
|---|---|---|
| Capability leak when two `setNumCapabilities` calls overlap; the next GC hangs | `issue.md` | [ghc/ghc#28109](https://gitlab.haskell.org/ghc/ghc/-/issues/28109) |
| Stop-the-world syncs stall for seconds while `setNumCapabilities` holds `stopTimer()` (backport request for 341ed474) | `issue-stoptimer.md` | [ghc/ghc#28110](https://gitlab.haskell.org/ghc/ghc/-/issues/28110) |
| Fix and testsuite test for the leak | `mr/` | ghc/ghc!XXXX (fill in after opening) |

Everything in `issue.md`, `issue-stoptimer.md` and `mr/` was run on a machine
and the raw output is under `evidence/`. Nothing here is a benchmark; the
numbers are hang counts and wall-clock stalls from loops of a small program.

## The minimal reproducer

`evidence/verify-a/scripts/CapRace.hs` depends on `base` only and is the file
quoted verbatim in `issue.md` (likewise `evidence/sync-lag/SyncLag.hs` in
`issue-stoptimer.md`).

```sh
ghc -O1 -threaded -rtsopts CapRace.hs -o caprace
./caprace conc +RTS -N2      # hangs on most runs on 2 to 10 cores (GHC 9.10.3, 9.12.4, 9.14.1)
./caprace serial +RTS -N2    # same calls under an MVar: never hangs
```

Loop drivers that classify each run as ok / idle hang / busy timeout are in
`evidence/verify-a/scripts/`; the tables are in `evidence/verify-a/RESULTS.md`.

## Layout

```
.
├── README.md                 this file
├── LICENSE                   BSD-3-Clause
├── issue.md                  issue 1: the capability leak that hangs the next GC
├── issue-stoptimer.md        issue 2: setNumCapabilities stalls while the timer is stopped
│                             (backport request for 341ed474)
├── issue.ja.md, issue-stoptimer.ja.md   Japanese translations of the two issue texts
├── mr/                       everything for the merge request
│   ├── rts-Schedule.c.patch  the fix, against master
│   ├── testsuite/tests/rts/  T28109.hs, T28109_c.c (native watchdog), all.T fragment
│   ├── changelog.d/28109
│   ├── COMMIT_MESSAGE.txt
│   └── MR_DESCRIPTION.md
├── evidence/
│   ├── verify-a/             minimal reproducer CapRace.hs; hang counts on a 10-core Mac
│   │                         and a 2-CPU Linux container; gdb/lldb dumps; -Ds traces
│   ├── verify-b/             earlier independent reproduction SetCapsRace.hs; Capability/Task
│   │                         state of three hangs; CI orphan-process lists
│   ├── plugin-test-repro/    narrowing the hang down from a real test suite to the RTS
│   ├── tasty-pure-repro/     the same hang with tasty alone, no project code
│   ├── rts-fix-check/        the fix verified by RTS-archive swapping and by a hadrian build
│   ├── sync-lag/             issue 2: SyncLag.hs, -C0 and no-stopTimer control runs
│   └── rts-fix-9.10.3.patch  the fix for the 9.10 branch (adds startTimer to the early return)
├── LOG.md                    chronological investigation log, mistakes included
├── notes-sources.md          wiki pages and tickets read; duplicate search; the tasty decision
├── publish-checklist.md      what was checked before publishing this repository
├── maintainer-checklist.md   the author's own to-do list (account, posting, MR)
├── mr-outline.md             early notes on the MR and the test
├── tasty-comment.md          optional comment for UnkindPartition/tasty#485
├── HANDOFF.md                hand-over notes between sessions (Japanese)
└── HANDOFF.en.md             English translation of HANDOFF.md
```

## Where to start

1. `issue.md`, "Summary": the mechanism. `setNumCapabilities` reads
   `n_capabilities` before `stopAllCapabilities` and releases only that many
   afterwards; whenever another call grows the array in between, the
   capabilities in between are left owned by a Task that has returned. Two
   observed interleavings and the two hang sites (`waitForCapability`,
   `waitForGcThreads`) follow.
2. `issue.md`, the results table under "Steps to reproduce": concurrent
   increases hang 198/200 (Mac) and 163/200 (2-CPU Linux); the three controls
   (serialised, decreases only, no-op) hang 0/200. `-fno-omit-yields` and a
   `-debug` RTS change nothing.
3. `evidence/verify-a/RESULTS.md`: the raw numbers behind that table, with the
   classification ok / idle_hang / busy_timeout explained at the top.
   `gdb/hang1-conc-waitForCapability.gdb.txt` shows the Task that still owns
   the leaked capabilities.
4. `mr/rts-Schedule.c.patch` and `mr/testsuite/tests/rts/T28109.hs`: a few
   lines that move the reads after `stopAllCapabilities` and re-check the
   early return, plus Note [setNumCapabilities and concurrent calls]; the test
   is six rounds of four concurrent calls followed by `performGC`, with a
   60 s watchdog on a native thread.
5. `evidence/rts-fix-check/RESULTS.md`, "Hadrian build of GHC master": the
   test fails unpatched in threaded1 and threaded2 and passes patched; 60/60
   loops, slowest 0.45 s. The sections above it verify the same fix without
   building GHC, and `evidence/rts-fix-check/README.md` explains the method
   and the `-optl-L` pitfall.
6. `issue-stoptimer.md`, "Summary": the separate stall. Released GHCs keep
   the timer stopped across the I/O-manager notification, so a yielding
   thread is re-queued at the front forever and the bound notification
   thread starves; `+RTS -C0` works around it; master fixed it in 341ed474.
   `evidence/sync-lag/RESULTS.md` has the measurements.
7. `LOG.md`: how each of the above was established, including what went
   wrong on the way.

## Environments

- macOS 27.0 (Darwin 27.0.0), Apple clang 21.0.0, 10 cores; GHC 9.10.3, 9.12.4
  and 9.14.1 from ghcup.
- Debian 13 aarch64 in a 2-CPU container, gcc 14.2.0, GHC 9.10.3 from ghcup.
- GHC master (20334e1d1f) built with hadrian, `--flavour=quick`, boot compiler
  9.14.1, for the testsuite run.

## LLM use

The investigation, the measurements, the drafts and the patch were produced
with Claude Code (Anthropic) under the direction of the author, who has read
and takes responsibility for every line posted upstream, as GHC's
[AI policy](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI) (P3,
P4) asks. Logs under `evidence/` are verbatim program output.

## Licence

BSD-3-Clause, see `LICENSE`.

Third-party material: `mr/rts-Schedule.c.patch`, `evidence/rts-fix-9.10.3.patch`
and the function excerpts `evidence/verify-b/ghc-*.c` contain code from GHC
(copyright The GHC Team, BSD-3-Clause,
<https://gitlab.haskell.org/ghc/ghc/-/blob/master/LICENSE>). The RTS files
read during the investigation are not copied here; the issue cites line
numbers against the immutable tags `ghc-9.10.3-release`, `ghc-9.12.4-release`,
`ghc-9.14.1-release` and master commit `7dedcf135e`.
