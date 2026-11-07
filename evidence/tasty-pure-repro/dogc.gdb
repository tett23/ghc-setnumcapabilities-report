define dogc
  frame function scheduleDoGC
  info locals
  print *idle_cap@n_capabilities
  print *task
end
thread apply all -s dogc
