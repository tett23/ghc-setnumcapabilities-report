#!/bin/sh
# plugrun.sh N BIN TAG1:args TAG2:args ... : parallel loops of a golem-plugin-test binary
N=$1; BIN=$2; shift 2
cd /w/modules/golem-plugin
for spec in "$@"; do
  tag=${spec%%:*}; args=${spec#*:}
  # shellcheck disable=SC2086
  sh /src/.plughang/caploop2.sh "$N" "$tag" "$BIN" $args &
done
wait
