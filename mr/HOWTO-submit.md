# Submitting the MR (tett23's steps, prepared 2026-11-10)

State of the GHC checkout `/Users/tett23/repositories/src/gitlab.haskell.org/ghc/ghc`:

- branch `wip/T28109-setNumCapabilities-race`, based on `origin/master`
  19ff36f2ae (fetched 2026-11-10);
- staged, not committed: `rts/Schedule.c` (the patch), `testsuite/tests/rts/T28109.hs`,
  `T28109_c.c`, the `all.T` entry (placed after `T27376`, the last upstream
  entry), `changelog.d/28109`;
- `git diff --cached --check` is clean.

## 1. Commit

```sh
cd /Users/tett23/repositories/src/gitlab.haskell.org/ghc/ghc
git commit -F /Users/tett23/Documents/ghc-setnumcapabilities-report/mr/COMMIT_MESSAGE.txt
```

`git config user.name` / `user.email` must be the identity you want on the
GHC history. The message ends with `Fixes #28109` and the
`Assisted-By: Claude Code (Anthropic)` trailer required by the AI policy.

## 2. Push to your fork

You need a fork of ghc/ghc on gitlab.haskell.org (new accounts must ask for
verification first; see `maintainer-checklist.md` step 2).

```sh
git remote add fork git@gitlab.haskell.org:<your-user>/ghc.git
git push -u fork wip/T28109-setNumCapabilities-race
```

## 3. Open the MR

Target `ghc/ghc` `master`. Title: the first line of the commit message.
Replace the template body with `mr/MR_DESCRIPTION.md` (keep the checklist
boxes). Prefix the title with `Draft:` until CI is green.

## 4. Fill in the MR number (required by CI)

`changelog.d/28109` has `mrs: !MMMMM`. The `mrs` field is required and CI's
`lint-changelog` job runs `changelog-d --validate --expect-mr <this MR>`, so
the entry must name this MR's number. After the MR exists:

```sh
sed -i '' 's/!MMMMM/!<number>/' changelog.d/28109
git add changelog.d/28109
git commit --amend --no-edit
git push --force-with-lease fork wip/T28109-setNumCapabilities-race
```

Then put the same number into `mr/changelog.d/28109`, `README.md` (the
`!XXXX` cell) and `mr/MR_DESCRIPTION.md` in this repository.

## 5. After CI

Remove `Draft:`, ask `@triagers` for ~RTS ~concurrency (the text in
`MR_DESCRIPTION.md` already does), and add a comment on #28109 naming the
test `testsuite/tests/rts/T28109` (the fixing-bugs wiki asks for this).
Backport labels are added by the maintainers after merge; the MR text asks
for them.
