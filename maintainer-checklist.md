# What tett23 must do personally

GHC rules read on 2026-10-17 (URLs in notes-sources.md).

## Account
1. Register on https://gitlab.haskell.org (GitHub mirror has issues disabled and
   accepts no PRs; its description says "Please submit issues and patches to
   GHC's Gitlab instance"). The web UI is behind Anubis; a normal browser works.
2. New accounts have reduced privileges (anti-spam). The "report-a-bug" wiki
   says to ask for approval through the mailing list or IRC
   (https://gitlab.haskell.org/ghc/ghc/-/wikis/mailing-lists-and-irc).
   To be able to *fork* (needed for an MR from your own fork) open an issue
   with the `get-verified` template ("I want to fix issue #NNNNN in ghc/ghc";
   tick the box about GHC-related projects only). Filing an issue itself may
   already be possible before verification; try it first.

## Posting the issue (do this first)
3. Re-read issue.md (all [FILL]/[VERIFY] markers were resolved on 2026-10-17
   with the verify-a/verify-b numbers; re-check them if you re-run anything).
   Keep the LLM-assistance line (GHC AI policy P4 — declaring use of an LLM is
   mandatory when it generated part of the material, and the declaration must
   be visible in the description).
4. New issue → template "default" → paste. Leave the `/label` quick actions.
   Make the title your own words if you prefer.
5. Done 2026-11-10: posted as #28109
   (https://gitlab.haskell.org/ghc/ghc/-/issues/28109). Still to do on the
   issue: add a line naming the test `testsuite/tests/rts/T28109` once the MR
   exists (fixing-bugs wiki asks for this). `issue-stoptimer.md` was posted
   as #28110 (https://gitlab.haskell.org/ghc/ghc/-/issues/28110) on
   2026-11-10.

## If you also submit the fix (MR)
6. Decide whether you are willing to take responsibility for every line of the
   patch, test and Note (AI policy P3/R1: understand and be able to explain
   every line; GHC recommends writing the final version yourself). If not,
   stop at the issue — that is fully acceptable.
7. Build GHC (hadrian) and run the new test both before and after the fix,
   many times, to show it catches the bug and is not flaky.
   Done once on 2026-11-07 (evidence/rts-fix-check/RESULTS.md, "Hadrian
   build"): the checkout /Users/tett23/repositories/src/gitlab.haskell.org/ghc/ghc
   has the patch and the test applied, uncommitted. Renamed to T28109 on
   2026-11-10 (files, all.T, the C file's message, the Haskell comment) and
   re-run through the driver; see RESULTS.md and
   evidence/rts-fix-check/hadrian-test-T28109.log.
8. Prepared 2026-11-10: branch `wip/T28109-setNumCapabilities-race` in the
   checkout, on origin/master 19ff36f2ae, with everything staged; the exact
   commands are in `mr/HOWTO-submit.md`. Original note: Push a branch to your fork (or to ghc/ghc if you get push rights), open an
   MR against `master`, replace the template text with your own description
   (see mr-outline.md §5), reference `#28109`, add `changelog.d/28109`, and
   mark `Draft:` until CI passes. One squashed commit; `Assisted-By: <tool>`
   trailer in the commit message if an LLM generated part of it.
9. Ask in a comment (@triagers) for labels ~RTS ~concurrency and, after merge,
   ~"backport needed:<branch>" for the maintained release branches (check
   current milestones; 9.10 is probably no longer maintained — ask).
10. If nobody reviews within a few days: comment mentioning @triagers and apply
    ~"Blocked on Review" (if you can).

## Licensing / sign-off
- GHC is BSD-3 licensed; there is no CLA and no DCO `Signed-off-by` requirement
  in CONTRIBUTING/HACKING, the MR template or the wiki pages read. Correct
  `git config user.name/user.email` is all that is asked. The AI-policy page
  notes that writing the patch yourself avoids copyright questions.
- Do not post anything that includes the Golem code or its tests; the
  reproducer is dependency-free on purpose.
