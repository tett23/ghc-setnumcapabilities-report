import sys, re
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()

note = '''/* ---------------------------------------------------------------------------
 * Note [setNumCapabilities and concurrent calls]
 * ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 * Nothing stops two Haskell threads from calling setNumCapabilities at the
 * same time.  The sync protocol (requestSync/stopAllCapabilities) makes sure
 * that only one of them changes the capability array at a time, but it does
 * not make the whole function atomic: a call may block in rts_lock() or in
 * requestSync() while another call is at work, and when it finally stops the
 * world, n_capabilities and enabled_capabilities may no longer be what they
 * were when it was entered.
 *
 * Therefore we must not read those variables before stopAllCapabilities()
 * returns and then rely on the values afterwards.  In particular:
 *
 *   - acquireAllCapabilities() (called by stopAllCapabilities()) acquires
 *     the n_capabilities capabilities that exist *at that moment*, and the
 *     final releaseAllCapabilities() must be given exactly that number.
 *     Passing a stale, smaller number leaves the newest capabilities with a
 *     running_task that points at a Task which has long moved on; the next
 *     stop-the-world sync (typically a GC) then waits for them forever.
 *
 *   - whether there is anything left to do (new_n_capabilities ==
 *     enabled_capabilities) must be decided after the world is stopped,
 *     because another call may have reached the same count meanwhile.
 *
 * The checks before rts_lock() are only a cheap early exit; they are
 * repeated once the world is stopped.
 * ------------------------------------------------------------------------- */

'''
anchor = 'void\nsetNumCapabilities (uint32_t new_n_capabilities USED_IF_THREADS)\n{'
assert s.count(anchor) == 1
s = s.replace(anchor, note + anchor)

old1 = '''    uint32_t old_n_capabilities = n_capabilities;

    if (new_n_capabilities == enabled_capabilities) {
        return;
'''
new1 = '''    uint32_t old_n_capabilities;

    // Early exit on a snapshot; repeated below once the world is stopped.
    // See Note [setNumCapabilities and concurrent calls].
    if (new_n_capabilities == enabled_capabilities) {
        return;
'''
assert s.count(old1) == 1; s = s.replace(old1, new1)

old2 = '''    debugTrace(DEBUG_sched, "changing the number of Capabilities from %d to %d",
               enabled_capabilities, new_n_capabilities);

    cap = rts_lock();
    task = cap->running_task;
'''
new2 = '''    cap = rts_lock();
    task = cap->running_task;
'''
assert s.count(old2) == 1; s = s.replace(old2, new2)

old3 = '''    stopAllCapabilities(&cap, task);

    if (new_n_capabilities < enabled_capabilities)
'''
has_timer = 'startTimer();\n\n    rts_unlock(cap);' in s
new3 = '''    stopAllCapabilities(&cap, task);

    // We now hold all the capabilities, so n_capabilities and
    // enabled_capabilities cannot change under us.  Only now may we read
    // them: see Note [setNumCapabilities and concurrent calls].
    // acquireAllCapabilities() took n_capabilities capabilities, and
    // releaseAllCapabilities() below must be given the same number.
    old_n_capabilities = n_capabilities;

    if (new_n_capabilities == enabled_capabilities) {
        // Another setNumCapabilities call did the work while we were
        // waiting for the sync.
        releaseAllCapabilities(old_n_capabilities, cap, task);
''' + ('''        startTimer();
''' if has_timer else '') + '''        rts_unlock(cap);
        return;
    }

    debugTrace(DEBUG_sched, "changing the number of Capabilities from %d to %d",
               enabled_capabilities, new_n_capabilities);

    if (new_n_capabilities < enabled_capabilities)
'''
assert s.count(old3) == 1; s = s.replace(old3, new3)
open(dst, 'w').write(s)
print("patched", dst, "timer" if has_timer else "no-timer")
