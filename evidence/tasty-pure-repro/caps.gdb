set pagination off
printf "n_capabilities=%d enabled=%d\n", n_capabilities, enabled_capabilities
print pending_sync
if pending_sync != 0
  print *pending_sync
  print *pending_sync->idle@n_capabilities
end
set $i = 0
while $i < n_capabilities
  set $c = capabilities[$i]
  printf "cap %d: %p running_task=%p disabled=%d idle=%u n_returning=%d returning_hd=%p spare_workers=%p n_run_queue=%d\n", $i, $c, $c->running_task, $c->disabled, $c->idle, $c->n_returning_tasks, $c->returning_tasks_hd, $c->spare_workers, $c->n_run_queue
  if $c->running_task != 0
    printf "   owner task %p: cap=%p wakeup=%d stopped=%d worker=%d bound=%p id=%lu\n", $c->running_task, $c->running_task->cap, $c->running_task->wakeup, $c->running_task->stopped, $c->running_task->worker, $c->running_task->incall, $c->running_task->id
  end
  if $c->returning_tasks_hd != 0
    printf "   returning hd task %p: cap=%p wakeup=%d id=%lu\n", $c->returning_tasks_hd, $c->returning_tasks_hd->cap, $c->returning_tasks_hd->wakeup, $c->returning_tasks_hd->id
  end
  set $i = $i + 1
end
info threads
thread apply all bt 12
