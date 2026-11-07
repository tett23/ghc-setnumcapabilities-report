scheduleDoGC (Capability **pcap, Task *task USED_IF_THREADS,
              bool force_major,
              bool is_overflow_gc,
              bool deadlock_detect,
              bool nonconcurrent)
{
    Capability *cap = *pcap;
    bool heap_census;
    uint32_t collect_gen;
    bool major_gc;
#if defined(THREADED_RTS)
    uint32_t gc_type;
    uint32_t i;
    uint32_t need_idle;
    uint32_t n_gc_threads;
    uint32_t n_idle_caps = 0, n_failed_trygrab_idles = 0;
    StgTSO *tso;
    bool *idle_cap;
      // idle_cap is an array (allocated later) of size n_capabilities, where
      // idle_cap[i] is rtsTrue if capability i will be idle during this GC
      // cycle.
#endif

    if (getSchedState() == SCHED_SHUTTING_DOWN) {
        // The final GC has already been done, and the system is
        // shutting down.  We'll probably deadlock if we try to GC
        // now.
        return;
    }

    heap_census = scheduleNeedHeapProfile(true);

    // We force a major collection if the size of the heap exceeds maxHeapSize.
    // We will either return memory until we are below maxHeapSize or trigger heapOverflow.
    bool mblock_overflow = RtsFlags.GcFlags.maxHeapSize != 0 && mblocks_allocated > BLOCKS_TO_MBLOCKS(RtsFlags.GcFlags.maxHeapSize);

    // Figure out which generation we are collecting, so that we can
    // decide whether this is a parallel GC or not.
    collect_gen = calcNeeded(force_major || heap_census || mblock_overflow , NULL);
    major_gc = (collect_gen == RtsFlags.GcFlags.generations-1);

#if defined(THREADED_RTS)
    if (getSchedState() < SCHED_INTERRUPTING
        && RtsFlags.ParFlags.parGcEnabled
        && collect_gen >= RtsFlags.ParFlags.parGcGen
        && ! oldest_gen->mark)
    {
        gc_type = SYNC_GC_PAR;
    } else {
        gc_type = SYNC_GC_SEQ;
    }

    // In order to GC, there must be no threads running Haskell code.
    // Therefore, for single-threaded GC, the GC thread needs to hold *all* the
    // capabilities, and release them after the GC has completed.  For parallel
    // GC, we synchronise all the running threads using requestSync().
    //
    // Other capabilities are prevented from running yet more Haskell threads if
    // pending_sync is set. Tested inside yieldCapability() and
    // releaseCapability() in Capability.c

    PendingSync sync = {
        .type = gc_type,
        .idle = NULL,
        .task = task
    };

    {
        SyncType prev_sync = 0;
        bool was_syncing;
        do {
            // If -qn is not set and we have more capabilities than cores, set
            // the number of GC threads to #cores.  We do this here rather than
            // in normaliseRtsOpts() because here it will work if the program
            // calls setNumCapabilities.
            //
            n_gc_threads = RtsFlags.ParFlags.parGcThreads;
            if (n_gc_threads == 0 &&
                enabled_capabilities > getNumberOfProcessors()) {
                n_gc_threads = getNumberOfProcessors();
            }

            // This calculation must be inside the loop because
            // enabled_capabilities may change if requestSync() below fails and
            // we retry.
            if (gc_type == SYNC_GC_PAR && n_gc_threads > 0) {
                if (n_gc_threads >= enabled_capabilities) {
                    need_idle = 0;
                } else {
                    need_idle = enabled_capabilities - n_gc_threads;
                }
            } else {
                need_idle = 0;
            }

            // We need an array of size n_capabilities, but since this may
            // change each time around the loop we must allocate it afresh.
            idle_cap = (bool *)stgMallocBytes(getNumCapabilities() *
                                              sizeof(bool),
                                              "scheduleDoGC");
            sync.idle = idle_cap;

            // When using +RTS -qn, we need some capabilities to be idle during
            // GC.  The best bet is to choose some inactive ones, so we look for
            // those first:
            uint32_t n_idle = need_idle;
            for (i=0; i < getNumCapabilities(); i++) {
                if (getCapability(i)->disabled) {
                    idle_cap[i] = true;
                } else if (n_idle > 0 &&
                           getCapability(i)->running_task == NULL) {
                    debugTrace(DEBUG_sched, "asking for cap %d to be idle", i);
                    n_idle--;
                    idle_cap[i] = true;
                } else {
                    idle_cap[i] = false;
                }
            }
            // If we didn't find enough inactive capabilities, just pick some
            // more to be idle.
            for (i=0; n_idle > 0 && i < getNumCapabilities(); i++) {
                if (!idle_cap[i] && i != cap->no) {
                    idle_cap[i] = true;
                    n_idle--;
                }
            }
            ASSERT(n_idle == 0);

            was_syncing = requestSync(pcap, task, &sync, &prev_sync);
            cap = *pcap;
            if (was_syncing) {
                stgFree(idle_cap);
            }
            if (was_syncing &&
                (prev_sync == SYNC_GC_SEQ || prev_sync == SYNC_GC_PAR) &&
                !(getSchedState() == SCHED_INTERRUPTING && force_major)) {
                // someone else had a pending sync request for a GC, so
                // let's assume GC has been done and we don't need to GC
                // again.
                // Exception to this: if SCHED_INTERRUPTING, then we still
                // need to do the final GC.
                return;
            }
            if (getSchedState() == SCHED_SHUTTING_DOWN) {
                // The scheduler might now be shutting down.  We tested
                // this above, but it might have become true since then as
                // we yielded the capability in requestSync().
                return;
            }
        } while (was_syncing);
    }

    stat_startGCSync(gc_threads[cap->no]);

    unsigned int old_n_capabilities = getNumCapabilities();

    interruptAllCapabilities();

    // The final shutdown GC is always single-threaded, because it's
    // possible that some of the Capabilities have no worker threads.

    if (gc_type == SYNC_GC_SEQ) {
        traceEventRequestSeqGc(cap);
    } else {
        traceEventRequestParGc(cap);
    }

    if (gc_type == SYNC_GC_SEQ) {
        // single-threaded GC: grab all the capabilities
        acquireAllCapabilities(cap,task);
    }
    else
    {
        // If we are load-balancing collections in this
        // generation, then we require all GC threads to participate
        // in the collection.  Otherwise, we only require active
        // threads to participate, and we set gc_threads[i]->idle for
        // any idle capabilities.  The rationale here is that waking
        // up an idle Capability takes much longer than just doing any
        // GC work on its behalf.

        if (RtsFlags.ParFlags.parGcNoSyncWithIdle == 0
            || (RtsFlags.ParFlags.parGcLoadBalancingEnabled &&
                collect_gen >= RtsFlags.ParFlags.parGcLoadBalancingGen))
        {
            for (i=0; i < n_capabilities; i++) {
                if (getCapability(i)->disabled) {
                    idle_cap[i] = tryGrabCapability(getCapability(i), task);
                    if (idle_cap[i]) {
                        n_idle_caps++;
                    }
                } else {
                    if (i != cap->no && idle_cap[i]) {
                        Capability *tmpcap = getCapability(i);
                        task->cap = tmpcap;
                        waitForCapability(&tmpcap, task);
                        n_idle_caps++;
                    }
                }
            }
        }
        else
        {
            for (i=0; i < n_capabilities; i++) {
                if (getCapability(i)->disabled) {
                    idle_cap[i] = tryGrabCapability(getCapability(i), task);
                    if (idle_cap[i]) {
                        n_idle_caps++;
                    }
                } else if (i != cap->no &&
                           getCapability(i)->idle >=
                           RtsFlags.ParFlags.parGcNoSyncWithIdle) {
                    idle_cap[i] = tryGrabCapability(getCapability(i), task);
                    if (idle_cap[i]) {
                        n_idle_caps++;
                    } else {
                        n_failed_trygrab_idles++;
                    }
                }
            }
        }
        debugTrace(DEBUG_sched, "%d idle caps, %d failed grabs", n_idle_caps, n_failed_trygrab_idles);

        for (i=0; i < n_capabilities; i++) {
            NONATOMIC_ADD(&getCapability(i)->idle, 1);
        }

        // For all capabilities participating in this GC, wait until
        // they have stopped mutating and are standing by for GC.
        waitForGcThreads(cap, idle_cap);

        // Stable point where we can do a global check on our spark counters
        ASSERT(checkSparkCountInvariant());
    }

#endif

    IF_DEBUG(scheduler, printAllThreads());

delete_threads_and_gc:
    /*
     * We now have all the capabilities; if we're in an interrupting
     * state, then we should take the opportunity to delete all the
     * threads in the system.
     * Checking for major_gc ensures that the last GC is major.
     */
    if (getSchedState() == SCHED_INTERRUPTING && major_gc) {
        deleteAllThreads();
#if defined(THREADED_RTS)
        // Discard all the sparks from every Capability.  Why?
        // They'll probably be GC'd anyway since we've killed all the
        // threads.  It just avoids the GC having to do any work to
        // figure out that any remaining sparks are garbage.
        for (i = 0; i < n_capabilities; i++) {
            getCapability(i)->spark_stats.gcd +=
                sparkPoolSize(getCapability(i)->sparks);
            // No race here since all Caps are stopped.
            discardSparksCap(getCapability(i));
        }
#endif
        setSchedState(SCHED_SHUTTING_DOWN);
    }

    /*
     * When there are disabled capabilities, we want to migrate any
     * threads away from them.  Normally this happens in the
     * scheduler's loop, but only for unbound threads - it's really
     * hard for a bound thread to migrate itself.  So we have another
     * go here.
     */
#if defined(THREADED_RTS)
    for (i = enabled_capabilities; i < n_capabilities; i++) {
        Capability *tmp_cap, *dest_cap;
        tmp_cap = getCapability(i);
        ASSERT(tmp_cap->disabled);
        if (i != cap->no) {
            dest_cap = getCapability(i % enabled_capabilities);
            while (!emptyRunQueue(tmp_cap)) {
                tso = popRunQueue(tmp_cap);
                migrateThread(tmp_cap, tso, dest_cap);
                if (tso->bound) {
                  traceTaskMigrate(tso->bound->task,
                                   tso->bound->task->cap,
                                   dest_cap);
                  tso->bound->task->cap = dest_cap;
                }
            }
        }
    }
#endif

    // Do any remaining idle GC work from the previous GC
    doIdleGCWork(cap, true /* all of it */);

    struct GcConfig config = {
        .collect_gen = collect_gen,
        .do_heap_census = heap_census,
        .overflow_gc = is_overflow_gc,
        .deadlock_detect = deadlock_detect,
        .nonconcurrent = nonconcurrent
    };

#if defined(THREADED_RTS)
    // reset pending_sync *before* GC, so that when the GC threads
    // emerge they don't immediately re-enter the GC.
    RELAXED_STORE(&pending_sync, 0);
    signalCondition(&sync_finished_cond);
    config.parallel = gc_type == SYNC_GC_PAR;
    GarbageCollect(config, cap, idle_cap);
#else
    GarbageCollect(config, cap, NULL);
#endif

    // If we're shutting down, don't leave any idle GC work to do.
    if (getSchedState() == SCHED_SHUTTING_DOWN) {
        doIdleGCWork(cap, true /* all of it */);
    }

    traceSparkCounters(cap);

    switch (getRecentActivity()) {
    case ACTIVITY_INACTIVE:
        if (force_major) {
            // We are doing a GC because the system has been idle for a
            // timeslice and we need to check for deadlock.  Record the
            // fact that we've done a GC and turn off the timer signal;
            // it will get re-enabled if we run any threads after the GC.
            setRecentActivity(ACTIVITY_DONE_GC);
#if !defined(PROFILING)
            stopTimer();
#endif
            break;
        }
        // fall through...

    case ACTIVITY_MAYBE_NO:
        // the GC might have taken long enough for the timer to set
        // recent_activity = ACTIVITY_MAYBE_NO or ACTIVITY_INACTIVE,
        // but we aren't necessarily deadlocked:
        setRecentActivity(ACTIVITY_YES);
        break;

    case ACTIVITY_DONE_GC:
        // If we are actually active, the scheduler will reset the
        // recent_activity flag and re-enable the timer.
        break;
    case ACTIVITY_YES:
        break;
    }

#if defined(THREADED_RTS)
    // Stable point where we can do a global check on our spark counters
    ASSERT(checkSparkCountInvariant());
#endif

    // The heap census itself is done during GarbageCollect().
    if (heap_census) {
        RELAXED_STORE(&performHeapProfile, false);
    }

#if defined(THREADED_RTS)

    // If n_capabilities has changed during GC, we're in trouble.
    ASSERT(n_capabilities == old_n_capabilities);

    if (gc_type == SYNC_GC_PAR)
    {
        for (i = 0; i < n_capabilities; i++) {
            if (i != cap->no) {
                if (idle_cap[i]) {
                    ASSERT(getCapability(i)->running_task == task);
                    task->cap = getCapability(i);
                    releaseCapability(getCapability(i));
                } else {
                    ASSERT(getCapability(i)->running_task != task);
                }
            }
        }
        task->cap = cap;

        // releaseGCThreads() happens *after* we have released idle
        // capabilities.  Otherwise what can happen is one of the released
        // threads starts a new GC, and finds that it can't acquire some of
        // the disabled capabilities, because the previous GC still holds
        // them, so those disabled capabilities will not be idle during the
        // next GC round.  However, if we release the capabilities first,
        // then they will be free (because they're disabled) when the next
        // GC cycle happens.
        releaseGCThreads(cap, idle_cap);
    }
#endif
    if (heap_overflow && getSchedState() == SCHED_RUNNING) {
        // GC set the heap_overflow flag.  We should throw an exception if we
        // can, or shut down otherwise.

        // Get the thread to which Ctrl-C is thrown
        StgTSO *main_thread = getTopHandlerThread();
        if (main_thread == NULL) {
            // GC set the heap_overflow flag, and there is no main thread to
            // throw an exception to, so we should proceed with an orderly
            // shutdown now.  Ultimately we want the main thread to return to
            // its caller with HeapExhausted, at which point the caller should
            // call hs_exit().  The first step is to delete all the threads.
            setSchedState(SCHED_INTERRUPTING);
            goto delete_threads_and_gc;
        }

        heap_overflow = false;
        const uint64_t allocation_count = getAllocations();
        if (RtsFlags.GcFlags.heapLimitGrace <
              allocation_count - allocated_bytes_at_heapoverflow ||
              allocated_bytes_at_heapoverflow == 0) {
            allocated_bytes_at_heapoverflow = allocation_count;
            // We used to simply exit, but throwing an exception gives the
            // program a chance to clean up.  It also lets the exception be
            // caught.

            // FIXME this is not a good way to tell a program to release
            // resources.  It is neither reliable (the RTS crashes if it fails
            // to allocate memory from the OS) nor very usable (it is always
            // thrown to the main thread, which might not be able to do anything
            // useful with it).  We really should have a more general way to
            // release resources in low-memory conditions.  Nevertheless, this
            // is still a big improvement over just exiting.

            // FIXME again: perhaps we should throw a synchronous exception
            // instead an asynchronous one, or have a way for the program to
            // register a handler to be called when heap overflow happens.
            throwToSelf(cap, main_thread, heapOverflow_closure);
        }
    }

#if defined(THREADED_RTS)
    stgFree(idle_cap);

    if (gc_type == SYNC_GC_SEQ) {
        // release our stash of capabilities.
        releaseAllCapabilities(n_capabilities, cap, task);
    }
#endif

    return;
}
