#!/bin/sh
cd /w/modules/golem-plugin
B=/w/dist-newstyle/build/aarch64-linux/ghc-9.10.3/golem-plugin-0.1.0/t/golem-plugin-test/build/golem-plugin-test/golem-plugin-test
"$B" -p '!/many.threads/' -l | tail -3
echo "concurrency tests listed: $("$B" -p '!/many.threads/' -l | grep -c 'many threads')"
