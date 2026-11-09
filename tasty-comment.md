<!--
Optional comment for UnkindPartition/tasty#485 (the revert of #457), to be
posted only after the GHC issue exists; replace #28109. Recommendation in
notes-sources.md: no separate tasty issue is needed, because tasty 1.5.5
already removed the call; this is information for the maintainers only.
-->

For the record, one more data point in favour of this revert.

While tracking down test-suite hangs on 2-CPU CI runners with tasty 1.5.4
and GHC 9.10.3, I found a GHC RTS bug: when two threads are inside
`setNumCapabilities` at the same time and the first one grows the
capability array, the second one leaks the new capabilities and the next
GC deadlocks (GHC issue #28109, with a dependency-free reproducer). In our
case the concurrent callers were test cases that raised the capability
count themselves, so tasty's own call in `runInParallel` (1.5.4) was not
one of the racing calls. But any framework-level `setNumCapabilities` makes
such races more likely in test suites, because test code that calls
`setNumCapabilities` is also the code most likely to run under `-j`. A
second, smaller problem in released GHCs (9.10–9.14) is that
`setNumCapabilities` keeps the RTS timer stopped while it runs the
I/O-manager notification, so a single call can stall for seconds when other
threads are busy (GHC issue #28110, fixed on GHC master).

So for users still on 1.5.4: start the binary with `+RTS -N` (or
`-with-rtsopts=-N`) and avoid calling `setNumCapabilities` from tests.
Nothing to do here since 1.5.5 no longer calls it; posting so that the
GHC issue is linked from the thread where `-j` implying `-N` was discussed.
