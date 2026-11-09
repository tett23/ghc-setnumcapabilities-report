# Sources actually read (2026-10-17) and findings

## GHC contribution rules
- https://raw.githubusercontent.com/ghc/ghc/master/HACKING.md — points to GitLab; "First time contributors are encouraged to get started by just sending a Merge Request" (README.md). CONTRIBUTING.md does not exist (404).
- https://raw.githubusercontent.com/ghc/ghc/master/.gitlab/issue_templates/default.md — bug template: Summary / Steps to reproduce / Expected behavior / Environment; `/label ~"T::bug"` `/label ~"needs triage"`. Other templates: documentation_issue, feature_request, get-verified, release_tracking.
- https://raw.githubusercontent.com/ghc/ghc/master/.gitlab/issue_templates/get-verified.md — new users have reduced privileges (no project creation/fork); request verification via this template.
- https://raw.githubusercontent.com/ghc/ghc/master/.gitlab/merge_request_templates/Default.md — MR checklist: issue reference, changelog.d entry or ~no-changelog, testsuite test, commit messages describing what they do with `#NNNNN`, squash fixups, `Draft:` prefix, @triagers + ~"Blocked on Review".
- GitLab wiki via API https://gitlab.haskell.org/api/v4/projects/ghc%2Fghc/wikis/<slug>:
  - report-a-bug — register, **ask for account approval** (spam workaround) via mailing list/IRC; search duplicates; "RTS bugs ... just create a new ticket"; repro case rules (small, no dependencies, reproducible).
  - working-conventions/fixing-bugs — 1. make sure the bug has an issue ("if it's a bug you have found yourself, add it to GitLab before you start work"); 2. add a testsuite test named after the bug number; 3. fix, comment with ticket number; 4. commits with `#NNNN`; 5. validate/CI; 6. open MR.
  - Contributing-a-Patch — "Every MR should have a ticket"; overview; changelog.d mandatory for user-facing changes; commit messages describe changes; regression tests; squash; Draft rules; backports via ~"backport needed:X.Y"; opening an MR (push to fork or ghc/ghc); §2.0 LLM policy.
  - contributing/AI — P1–P4, R1: must declare LLM-generated material in description and `Assisted-By:` commit trailer; human must understand every line; tickets have looser criteria but still P4.
  - contributing/changelog — `changelog.d/<name>` with required fields section/synopsis/issues/mrs, cabal-style field syntax; `no-changelog` label otherwise.
  - building/running-tests/adding — all.T `test(name, setup, fn, args)`; name tests TNNNN.
  - gitlab/issues — triage protocol: labels, priority (crash/incorrect result = P::highest), milestones; `Closes #NNNN` auto-closes.
- GitHub mirror: https://api.github.com/repos/ghc/ghc — description "Mirror ... Please submit issues and patches to GHC's Gitlab instance"; has_issues=false; PRs exist but are closed unmerged (e.g. #284–#286).
- Labels API needs auth (401); label names taken from issues seen: RTS, concurrency, runtime crash, P::*, T::bug, backport needed, llm-derived::reproducer (exists on #27635).

## Duplicate search, second pass (2026-10-17, GitLab REST API, unauthenticated)
Raw results (API JSON, removed from the published folder on 2026-11-08): search_*.json, mr_search_*.json, issue_{20144,17261,22926,17289}.json,
commits_Schedule_c.json. Script: searches paged with per_page=100 and X-Next-Page.
- Extra issue queries: waitForGcThreads, stopAllCapabilities, moreCapabilities, running_task,
  "setNumCapabilities hang" (0 hits), "setNumCapabilities GC", "capabilities leak", n_capabilities.
  Nothing new that matches. New tickets looked at and ruled out:
  - #20144 (closed 2021-08): GC entry deadlock on AArch64/Darwin while entering GC; no
    setNumCapabilities involved; fixed in 2021.
  - #17261 (closed 2020-12): TSAN data race in stopCapability/shouldYieldCapability; memory
    ordering, not a leaked capability.
  - #22926 / #22927 (closed 2023-03): non-moving GC vs setNumCapabilities segment arrays; crash,
    not a hang, non-moving only.
  - #17289 (open): TSAN race setNumCapabilities vs itimer; no hang.
- Merge-request queries: setNumCapabilities (13 MRs, all backport batches or unrelated fixes:
  !13692 MAX_N_CAPS assert, !10089 zeroSlop, !10055 createBCOs, !8459 IO manager, !9372 memory
  ordering), releaseAllCapabilities (0), old_n_capabilities (0), stopAllCapabilities (0).
  No open or merged MR touches the old_n_capabilities snapshot.
- Commits to rts/Schedule.c since 2024-06 (API, 22 commits): the only ones touching
  setNumCapabilities are f08a72eb / 71f050b7 (MAX_N_CAPS assert and max_n_capabilities, Dec 2024)
  and 341ed474 (remove stopTimer, Jun 2026). None moves the snapshot after stopAllCapabilities;
  master 7dedcf135e still has the pattern (Schedule.c:2281/2283/2300/2376).
- Comment threads of #22989 and #18808: not readable from this session (the notes endpoint
  returns 401 without a token, and the web UI (Anubis) refused the in-app browser). tett23 read
  them while logged in on 2026-11-10: nothing of substance for this report, no mention of the
  stale old_n_capabilities. No change to the issue text.
- Conclusion unchanged: no existing ticket or MR describes the leak; file a new issue and
  cross-reference #18808 and #22989 as "possibly the same test, different symptom".

## Duplicate search (GitLab issues API, scope=all)
Queries: setNumCapabilities, releaseAllCapabilities, old_n_capabilities, acquireAllCapabilities, "setNumCapabilities deadlock", "concurrent setNumCapabilities".
No ticket describes the stale old_n_capabilities / concurrent-increase leak. Closest:
- #8209 (closed, 7.8): old race, foreign-call return vs capability array move.
- #14707 (closed): idle_caps mutated after requestSync; threads stuck in gcWorkerThread.
- #18808 (open): TSAN race setNumCapabilities vs scheduleDoGC in setnumcapabilities001.
- #22989 (open): setnumcapabilities001 timeout; single setter thread → probably different.
- #12038 (open): shutdown vs requestSync.
- #27460, #27473 (open, 2026): returning_tasks vs pending_sync priority; GC sync via waitForCapability — the protocol our hang goes through.
- #27635, #27652 (open, 2026): eventlog-related deadlock/crash with setNumCapabilities; different.

## Source checked
- Local partial clone /Users/tett23/repositories/src/github.com/ghc/ghc (tag ghc-9.10.3-release; origin/master 7dedcf135e). rts/Schedule.c lines verified: 1543 (acquireAllCapabilities loop over getNumCapabilities()), 1572 (releaseAllCapabilities(n,...)), 1789 (waitForCapability on idle caps in scheduleDoGC), 2272/2274/2297/2371 (setNumCapabilities). Master: 2281/2283/2376; function otherwise same except stopTimer/startTimer removed and IO-manager call renamed.
- /Users/tett23/repositories/src/github.com/UnkindPartition/tasty (tasty-1.5.4): core/Test/Tasty/Parallel.hs:46-48 calls setNumCapabilities when ncap < nthreads.
- testsuite/tests/concurrent/should_run/setnumcapabilities001.hs + all.T (only_ways threaded1/threaded2/nonmoving_thr/profthreaded, req_target_smp, req_ghc_smp, fragile(22989)); testsuite/tests/rts/all.T T22012 passes a C file to compile_and_run.
- changelog.d/config on master: section keys include `rts`.

## Decision: issue first, then (optionally) MR
- fixing-bugs step 1 and Contributing-a-Patch §2.1 require a ticket before/alongside any MR; the MR template's first checkbox asks for the issue number.
- Small RTS fixes may go straight to an MR in practice, but the MR still needs a ticket; and here the maintainer wants the bug on record regardless of who fixes it.
- A testsuite test is "really helpful"/"as applicable" (not a hard gate), but for a bug fix it is the norm (fixing-bugs step 2), and the reviewers will expect one.

## tasty (HANDOFF item 5), checked 2026-11-07
- Local clone fetched: origin/master is "Release tasty-1.5.5"; `core/tasty.cabal` version 1.5.5;
  `core/Test/Tasty/Parallel.hs` on origin/master no longer contains `setNumCapabilities`.
  Hackage lists tasty-1.5.5 as a normal version (preferred-versions endpoint).
- CHANGELOG 1.5.5: "Revert making `-j` to entail `+RTS -N` automatically, restoring the behaviour
  from tasty-1.5.3 and earlier (#485)". GitHub API: PR #485 merged 2026-10-10 ("After several attempts
  to alleviate undesirable effects of #457 (#482, #483) ... revert #457"); PR #457 merged 2025-10-04,
  released in 1.5.4 (2025-03-31 per CHANGELOG). Search for "setNumCapabilities" in the repo's issues/PRs:
  #455, #457, #482, #483 only; none mentions the RTS deadlock.
- What tasty's call actually did in our hang: `runInParallel` calls `setNumCapabilities nthreads` once,
  before forking the worker threads, so it was a *serial* call that only changed the starting count
  (1 -> number of processors). The racing calls were the test cases' own `setNumCapabilities 8`
  (verify-b's `SetCapsRace.hs` models exactly this: one startup call, then two concurrent raises).
- Decision: no tasty issue. The behaviour is already gone in 1.5.5, and tasty's call was not one of
  the racing calls. An optional informational comment on #485 (draft: `tasty-comment.md`) can link the
  GHC issue once it exists, as a reason not to reintroduce #457 and as advice for 1.5.4 users
  (`-with-rtsopts=-N`, no `setNumCapabilities` in tests). HANDOFF said #485 was unreleased; it is
  released now.
