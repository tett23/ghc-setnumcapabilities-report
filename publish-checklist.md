# Before publishing this folder as the repository linked from the issue

Checked on 2026-11-08 against the folder as it stands (not yet a git
repository). Items are ordered by how much a GHC reader would notice them.

## Must do

1. ~~Add a licence~~ Done 2026-11-08: BSD-3-Clause in `LICENSE`, README
   updated. Original note: **Add a licence** (`LICENSE`). Without one, nothing here may legally be
   reused, including the test program a maintainer might want to adapt. GHC
   itself is BSD-3-Clause; the MR content is submitted under GHC's licence
   anyway. BSD-3-Clause (or MIT) for the whole folder is the simplest choice.
   `README.md` has a `[FILL]` for it.
2. Done 2026-11-08: `evidence/rts-9.10.3-source/` removed; the small GHC
   excerpts under `evidence/verify-b/ghc-*.c` and the two patches stay, with a
   third-party notice in `README.md`. Original note: **Decide what to do with
   `evidence/rts-9.10.3-source/` and
   `raw/Schedule_master.c`.** They are verbatim copies of GHC source
   (copyright The GHC Team, BSD-3). Either add GHC's `LICENSE` file next to
   them (the ghq checkout has it), or delete them and point readers at the
   immutable tags (`ghc-9.10.3-release`, commit `7dedcf135e`); the issue
   already cites line numbers per tag. Deleting is cleaner.
3. ~~Drop `raw/`~~ Done 2026-11-08: moved out of the folder (it held GitLab API
   dumps of other people's tickets and copies of GHC docs; `notes-sources.md`
   lists what was read). `raw/` stays in `.gitignore`. `raw/Schedule_master.c`
   went with it, so item 2 is now only about `evidence/rts-9.10.3-source/`.
4. **Make `README.md` the entry point and fill the placeholders** (`NNNNN`,
   `MMMMM`, `XXXX`) once the issue and MR numbers exist. The same numbers go
   into `mr/` (`TNNNNN`, `changelog.d/NNNNN`) per `maintainer-checklist.md`.
5. Done 2026-11-08 (https://github.com/tett23/ghc-setnumcapabilities-report,
   first commit 252127e). Original note: **Add the repository URL to the issue
   texts.** Neither `issue.md` nor
   `issue-stoptimer.md` has a line for it yet. Suggested place: the end of
   "Steps to reproduce" in `issue.md` ("Full logs, gdb dumps and `-Ds` traces:
   <URL>, `evidence/verify-a`, `evidence/verify-b`") and the "Evidence" line of
   `issue-stoptimer.md` (`evidence/sync-lag/`). The GHC wiki (report-a-bug)
   asks for reproducers larger than a few modules as a git repository; ours is
   one file, so the repository is supplementary, and the issue should stay
   self-contained (it is).

## Should do

6. **Golem material.** `maintainer-checklist.md` says not to post anything
   containing Golem code or tests, but the folder contains
   `evidence/plugin-fix.diff` and
   `evidence/verify-b/proposed-fix-applied-in-scratch.diff` (diffs of Golem's
   cabal files and test modules), scripts under `evidence/plugin-test-repro/`
   that `cd` into Golem's modules, and CI orphan-process lists naming Golem test
   binaries. Golem is public on GitHub (tett23/golem), so this is not a
   secrecy problem, but the two diffs add nothing to the GHC report. Either
   delete them or keep them and relax the checklist line. The scripts and the
   CI list are evidence for the "4 hung tests all call setNumCapabilities"
   claim and can stay. Done 2026-11-08: the two diffs were removed; the
   scripts and the CI list stay.
7. **`repro/`.** `repro/Race.hs` duplicates
   `evidence/plugin-test-repro/Race.hs`; `repro/Repro.hs` is marked
   "UNVERIFIED… do not post", and `repro/run.sh` drives it. Publishing an
   unverified reproducer invites a maintainer to try it first. Options: delete
   `repro/`, or replace it with the verified `CapRace.hs` plus the two-line
   build/run instructions from `README.md`. Done 2026-11-08: `repro/`
   removed; `README.md` carries the build line for `CapRace.hs`.
8. **Reproducer copies differ from the issue text in comments only.**
   `evidence/verify-a/scripts/CapRace.hs` still says "hypothesis A" (a label
   from the investigation); the issue quotes a copy with neutral comments.
   `evidence/sync-lag/SyncLag.hs` has an extra `both` mode and longer
   comments; the issue quotes the trimmed version. Harmless, but a reader who
   diffs them will wonder. Either copy the issue versions over the evidence
   files (code is identical, so the measurements still apply) or say in
   `README.md` that the quoted copies are trimmed. Done 2026-11-08: both
   evidence files now equal the code blocks in the issue texts (the unused
   `both` mode of SyncLag was dropped; no measurement used it); both compile
   with GHC 9.10.3.
9. **`HANDOFF.md` is Japanese and names local containers and paths.** It is
   honest process documentation and can stay; `README.md` says it is working
   notes. If you would rather not publish it, move it and
   `maintainer-checklist.md` out of the folder; `LOG.md` and
   `notes-sources.md` carry the same facts in English.
10. **Evidence folders without an index.** `evidence/verify-b/`,
    `evidence/plugin-test-repro/` and `evidence/tasty-pure-repro/` have no
    README. `HANDOFF.md` describes them (in Japanese) and `README.md` now does
    in English; a one-paragraph `README.md` in each would still help, in
    particular for verify-b's three gdb state dumps (which hang is which).

## Could do

11. **Local paths and tool names in scripts.** `/Users/tett23/…` appears in
    the hadrian and RTS-swap scripts and logs; `/w`, `/v`, `/root/build` in the
    container scripts; `ghc-9.10.3` vs `ghc` differs between Mac and container
    scripts. Readers will not rerun those scripts as they are, which is fine
    for evidence, but `evidence/rts-fix-check/README.md` should say so (it
    describes the method; add "paths are the author's machine").
12. **Large files.** `evidence/sync-lag/trace-dbg-N2-slow.txt` (1.2 MB) and the
    verify-b `-Ds` trace (140 KB) are text; GitHub renders them. No action
    unless you want to gzip them.
13. **Nothing secret was found**: no tokens, e-mail addresses or keys (grep
    over the folder for `ghp_`, `glpat-`, `token`, `secret`, `password`,
    `Authorization`); the only hits are GHC source comments.
14. Done 2026-11-08: `git init`, commit 252127e, pushed to the public
    repository above. Original note: **`git init` and first commit** after items 1–3, so the issue can link a
    commit hash rather than a moving branch. Commit the `mr/` files as they
    are; the GHC MR itself is created from the GHC checkout, not from here.

## What was verified for this list

- Folder listing, sizes and a grep for private strings (done 2026-11-08).
- GHC wiki "report-a-bug" (`raw/wiki_report-a-bug.json`): reproducers larger
  than a few modules should be a git repository; smaller ones inline.
- GHC AI policy: P3/P4 apply to tickets and MRs; a declaration in `README.md`
  mirrors the one in the issue texts.
- `git ls-remote https://github.com/tett23/golem.git` succeeds anonymously, so
  Golem is public.
