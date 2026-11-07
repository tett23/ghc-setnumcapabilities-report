set pagination off
set print pretty off
p n_capabilities
p enabled_capabilities
p max_n_capabilities
p *pending_sync
p sched_state
p all_tasks
set $i = 0
while $i < n_capabilities
  set $c = capabilities[$i]
  printf "cap %d: running_task=%p disabled=%d n_returning=%d returning_hd=%p spare=%p n_spare=%d run_queue=%d suspended=%d in_haskell=%d\n", $c->no, $c->running_task, $c->disabled, $c->n_returning_tasks, $c->returning_tasks_hd, $c->spare_workers, $c->n_spare_workers, $c->n_run_queue, $c->n_suspended_ccalls, $c->in_haskell
  set $i = $i + 1
end
set $t = all_tasks
while $t != 0
  printf "task %p: id=%lu cap=%d worker=%d stopped=%d wakeup=%d running_finalizers=%d incall_tso=%p preferred=%d next=%p\n", $t, $t->id, $t->cap ? $t->cap->no : -1, $t->worker, $t->stopped, $t->wakeup, $t->running_finalizers, $t->incall ? $t->incall->tso : 0, $t->preferred_capability, $t->next
  set $t = $t->all_next
end
thread apply all bt 12
