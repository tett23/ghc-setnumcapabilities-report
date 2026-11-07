setNumCapabilities (uint32_t new_n_capabilities USED_IF_THREADS)
{
#if !defined(THREADED_RTS)
    if (new_n_capabilities != 1) {
        errorBelch("setNumCapabilities: not supported in the non-threaded RTS");
    }
    return;
#elif defined(NOSMP)
    if (new_n_capabilities != 1) {
        errorBelch("setNumCapabilities: not supported on this platform");
    }
    return;
#else
    Task *task;
    Capability *cap;
    uint32_t n;
    Capability *old_capabilities = NULL;
    uint32_t old_n_capabilities = n_capabilities;

    if (new_n_capabilities == enabled_capabilities) {
        return;
    } else if (new_n_capabilities <= 0) {
        errorBelch("setNumCapabilities: Capability count must be positive");
        return;
    } else if (new_n_capabilities > max_n_capabilities) {
        // See Note [Capabilities array sizing] in rts/Capability.c.
        errorBelch("setNumCapabilities: Attempt to increase capability count beyond maximum capability count %" PRIu32 "; clamping...\n", max_n_capabilities);
        new_n_capabilities = max_n_capabilities;
    }

    debugTrace(DEBUG_sched, "changing the number of Capabilities from %d to %d",
               enabled_capabilities, new_n_capabilities);

    cap = rts_lock();
    task = cap->running_task;


    // N.B. We must stop the interval timer while we are changing the
    // capabilities array lest handle_tick may try to context switch
    // an old capability. See #17289.
    stopTimer();

    stopAllCapabilities(&cap, task);

    if (new_n_capabilities < enabled_capabilities)
    {
        // Reducing the number of capabilities: we do not actually
        // remove the extra capabilities, we just mark them as
        // "disabled". This has the following effects:
        //
        //   - threads on a disabled capability are migrated away by the
        //     scheduler loop
        //
        //   - disabled capabilities do not participate in GC
        //     (see scheduleDoGC())
        //
        //   - No spark threads are created on this capability
        //     (see scheduleActivateSpark())
        //
        //   - We do not attempt to migrate threads *to* a disabled
        //     capability (see schedulePushWork()).
        //
        // but in other respects, a disabled capability remains
        // alive.  Threads may be woken up on a disabled capability,
        // but they will be immediately migrated away.
        //
        // This approach is much easier than trying to actually remove
        // the capability; we don't have to worry about GC data
        // structures, the nursery, etc.
        //
        for (n = new_n_capabilities; n < enabled_capabilities; n++) {
            getCapability(n)->disabled = true;
            traceCapDisable(getCapability(n));
        }
        enabled_capabilities = new_n_capabilities;
    }
    else
    {
        // Increasing the number of enabled capabilities.
        //
        // enable any disabled capabilities, up to the required number
        for (n = enabled_capabilities;
             n < new_n_capabilities && n < n_capabilities; n++) {
            getCapability(n)->disabled = false;
            traceCapEnable(getCapability(n));
        }
        enabled_capabilities = n;

        if (new_n_capabilities > n_capabilities) {
#if defined(TRACING)
            // Allocate eventlog buffers for the new capabilities.  Note this
            // must be done before calling moreCapabilities(), because that
            // will emit events about creating the new capabilities and adding
            // them to existing capsets.
            tracingAddCapabilities(n_capabilities, new_n_capabilities);
#endif

            // Resize the capabilities array
            // NB. after this, capabilities points somewhere new.  Any pointers
            // of type (Capability *) are now invalid.
            moreCapabilities(n_capabilities, new_n_capabilities);

            // Resize and update storage manager data structures
            ACQUIRE_SM_LOCK;
            storageAddCapabilities(n_capabilities, new_n_capabilities);
            RELEASE_SM_LOCK;
        }
    }

    // update n_capabilities before things start running
    if (new_n_capabilities > n_capabilities) {
        RELAXED_STORE(&n_capabilities, new_n_capabilities);
        RELAXED_STORE(&enabled_capabilities, new_n_capabilities);
    }

    // We're done: release the original Capabilities
    releaseAllCapabilities(old_n_capabilities, cap,task);

    // We can't free the old array until now, because we access it
    // while updating pointers in updateCapabilityRefs().
    if (old_capabilities) {
        stgFree(old_capabilities);
    }

    // Notify IO manager that the number of capabilities has changed.
    rts_evalIO(&cap, ioManagerCapabilitiesChanged_closure, NULL);

    startTimer();

    rts_unlock(cap);

#endif // THREADED_RTS
}
