#!/bin/sh
cd /w/modules/golem-plugin
L=/src/.plughang/caploop.sh
sh $L 300 fix-a /t/plugin-fixed &
sh $L 300 fix-b /t/plugin-fixed &
sh $L 300 fix-c /t/plugin-fixed &
sh $L 300 fix-nonet /t/plugin-fixed -p '!/ADR 0002/ && !/TLS root/' &
wait
