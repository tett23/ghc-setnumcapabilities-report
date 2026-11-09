<!-- Replace the MR template text with this. MMMMM = this MR's number. -->

Fixes #28109.

`setNumCapabilities` read `n_capabilities` and `enabled_capabilities` before
`stopAllCapabilities()` and used the stale values afterwards. When another
call grew the capability array in between, the later caller acquired all the
capabilities that existed at the sync but released only the old count, leaving
the newest capabilities with a dangling `running_task`. The next stop-the-world
sync (usually a GC) then waited for them forever, in `waitForCapability` or in
the `waitForGcThreads` loop. The issue has the analysis, a `+RTS -Ds` trace
and gdb dumps.

This MR reads the counts after the world is stopped, re-checks whether there
is anything left to do (and releases what it holds if not), and adds
`Note [setNumCapabilities and concurrent calls]` stating the invariant:
`releaseAllCapabilities` must be given the number of capabilities that
`acquireAllCapabilities` saw.

Where to look: `rts/Schedule.c`, `setNumCapabilities`, the block right after
`stopAllCapabilities`.

Test: `testsuite/tests/rts/T28109` (threaded1, threaded2). It runs six
rounds of four concurrent `setNumCapabilities` calls with distinct,
increasing targets and forces a GC after each round; a watchdog on a
native thread (started from C, so it does not depend on the RTS) fails
the test after 60 s instead of waiting for the testsuite timeout.
Verified on a hadrian build of master (20334e1d1f, `--flavour=quick`,
macOS aarch64, 10 cores): through the testsuite driver the test fails
unpatched in both threaded1 and threaded2 (exit code 1 from the watchdog)
and passes patched in both ways; the patched stage1-built binaries pass
60 / 60 runs per way, slowest 0.45 s. Earlier, with the patched
`Schedule.c` swapped into the GHC 9.10.3 RTS archives, the unfixed RTS
failed 19 / 20 runs on the same machine and 37 / 40 in a 2-CPU Linux
container, while the fixed RTS passed 120 / 120 on each.

LLM assistance (per https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI):
Claude Code (Anthropic) was used to analyse the RTS source, to write the
reproducer and the first version of the patch, test and Note, and to draft
this text. I have reviewed and revised every line and take full
responsibility for it (P3); the commit carries an `Assisted-By:` trailer.

- [x] This MR solves the problem described in #28109
- [x] Changelog entry added in `changelog.d/28109`
- [x] Testcase added: `testsuite/tests/rts/T28109`
- [x] Commit message describes what it does, referring to #28109

@triagers: could you add ~RTS ~concurrency? The bug is present in every
release since at least 9.10, so a backport to the maintained branches would
be welcome.
