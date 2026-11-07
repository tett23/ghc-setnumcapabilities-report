# Checking the RTS fix without building GHC (2026-10-17, macOS, GHC 9.10.3 from ghcup)

The fix only touches `rts/Schedule.c`, so instead of a hadrian build the
patched file was compiled on its own and swapped into copies of the shipped
RTS archives.

1. `git archive ghc-9.10.3-release rts | tar -x` gives the 9.10.3 RTS source
   (the installed `rts-1.0.2/include` supplies `ghcautoconf.h`,
   `ghcplatform.h`, `DerivedConstants.h`).
2. `patch.py ORIG NEW` applies the same edit to 9.10.3 and master
   (it adds `startTimer()` to the early return only when the file has
   the 9.10.x `stopTimer()/startTimer()` pair). The resulting diffs are
   `mr/rts-Schedule.c.patch` (master) and `evidence/rts-fix-9.10.3.patch`.
3. `ccrts.sh SRCDIR OUTDIR` compiles `Schedule.c` for the `thr`
   (`-O2 -DTHREADED_RTS`) and `thr_debug` (`-O0 -g -DDEBUG -DTHREADED_RTS`)
   ways with the flags hadrian/rts.cabal use (`-DCOMPILING_RTS
   -DFS_NAMESPACE=rts -fno-strict-aliasing -fno-common -fwrapv`).
   Compiling the *unmodified* file this way gives an object whose defined
   and undefined symbol sets are identical to `Schedule.thr_o` /
   `Schedule.thr_debug_o` in the shipped archives, which is the check that
   the flags are right.
4. For each of `orig` (unmodified recompile, the control) and `fixed`:
   copy `libHSrts-1.0.2_thr.a` and `libHSrts-1.0.2_thr_debug.a`, replace
   the member with `ar rs libHSrts-1.0.2_thr.a Schedule.thr_o`, and link the
   test programs with GHC's `-L<that dir>` flag. `ghc -v` shows that `-L`
   is placed before the package directories, and the Mach-O linker uses
   `-search_paths_first`, so the swapped archive wins. (`-optl-L` does
   *not* work: GHC appends it after the package directories, and the first
   attempt silently measured the shipped RTS twice. Check the binary:
   `otool -tV BIN | awk '/^_setNumCapabilities:/,/^_[a-z]/' | wc -l` is 172
   for the shipped 9.10.3 object, 180 for the recompiled original and 201
   for the fixed one.)
5. `runmany.sh BIN N TIMEOUT args...` runs a binary N times and classifies
   each run as ok / idle_hang (alive after TIMEOUT with no CPU use) /
   busy_timeout (alive and using CPU) / other (non-zero exit).

Results are in `RESULTS.md` next to this file.
