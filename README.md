# GHC `setNumCapabilities` race: report and evidence

Supporting material for two GHC issues and one merge request:

| What | File | Upstream |
|---|---|---|
| Capability leak when two `setNumCapabilities` calls overlap; the next GC hangs | `issue.md` | ghc/ghc#NNNNN (fill in after posting) |
| Stop-the-world syncs stall for seconds while `setNumCapabilities` holds `stopTimer()` (backport request for 341ed474) | `issue-stoptimer.md` | ghc/ghc#MMMMM (fill in after posting) |
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

- `issue.md`, `issue-stoptimer.md`: the issue texts as posted (GHC default template).
- `mr/`: `rts-Schedule.c.patch` (against master), the testsuite test
  `TNNNNN.hs` / `TNNNNN_c.c` / `all.T` fragment, `changelog.d/`, the commit
  message and the MR description.
- `evidence/verify-a/`: the minimal reproducer, hang counts on macOS (10 cores)
  and a 2-CPU Linux container, gdb/lldb backtraces and `+RTS -Ds` traces of hung
  processes.
- `evidence/verify-b/`: an earlier independent reproduction, gdb dumps of
  `Capability`/`Task` state for three hangs, and the CI job logs that showed
  which test binaries were left orphaned.
- `evidence/plugin-test-repro/`, `evidence/tasty-pure-repro/`: how the hang was
  narrowed down from a real test suite (tasty 1.5.4, which called
  `setNumCapabilities` from `runInParallel`) to the RTS.
- `evidence/rts-fix-check/`: the fix verified two ways: by recompiling
  `rts/Schedule.c` into a copy of the shipped 9.10.3 RTS archive (`README.md`
  explains the method and one pitfall), and by a hadrian build of GHC master
  with the patch and the new test (`hadrian-*.log`, `RESULTS.md`).
- `evidence/sync-lag/`: the second phenomenon (stalls, not hangs), its
  reproducer `SyncLag.hs`, and the `-C0` / no-`stopTimer` control runs.
- `LOG.md`: chronological log of the investigation, including the mistakes.
- `notes-sources.md`: the GHC wiki pages and tickets read, and the duplicate
  search (tickets #8209, #14707, #18808, #20144, #22989, #27460, #27473).
- `HANDOFF.md`, `maintainer-checklist.md`, `mr-outline.md`: working notes
  (`HANDOFF.md` is in Japanese).

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
