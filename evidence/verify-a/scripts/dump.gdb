set pagination off
set print pretty off
printf "n_capabilities=%u enabled_capabilities=%u n_gc_entered=%u n_gc_threads=%u\n", n_capabilities, enabled_capabilities, n_gc_entered, n_gc_threads
print pending_sync
if pending_sync != 0
  print *pending_sync
  printf "pending_sync->task=%p os id=%lu\n", pending_sync->task, pending_sync->task->id
  set $j = 0
  while $j < n_capabilities
    printf "  idle[%u]=%d\n", $j, pending_sync->idle[$j]
    set $j = $j + 1
  end
end
set $i = 0
while $i < n_capabilities
  set $c = capabilities[$i]
  printf "cap %u @%p: running_task=%p returning_tasks_hd=%p n_returning_tasks=%u disabled=%d spare_workers=%p n_spare_workers=%u interrupt=%d run_queue_hd=%p gc_threads.wakeup=%d\n", $i, $c, $c->running_task, $c->returning_tasks_hd, $c->n_returning_tasks, $c->disabled, $c->spare_workers, $c->n_spare_workers, $c->r.rHpLim == 0, $c->run_queue_hd, gc_threads[$i]->wakeup
  if $c->running_task != 0
    printf "    running_task os_id=%lu stopped=%d task->cap=%p (cap no %d) wakeup=%d\n", $c->running_task->id, $c->running_task->stopped, $c->running_task->cap, $c->running_task->cap ? $c->running_task->cap->no : -1, $c->running_task->wakeup
  end
  set $t = $c->returning_tasks_hd
  while $t != 0
    printf "    returning task %p os_id=%lu task->cap=%p\n", $t, $t->id, $t->cap
    set $t = $t->next
  end
  set $t = $c->spare_workers
  while $t != 0
    printf "    spare worker %p os_id=%lu task->cap=%p wakeup=%d\n", $t, $t->id, $t->cap, $t->wakeup
    set $t = $t->next
  end
  set $i = $i + 1
end
info threads
thread apply all bt 12
