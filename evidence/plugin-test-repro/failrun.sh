#!/bin/sh
cd /w/modules/golem-plugin
L=/src/.plughang/caploop2.sh
sh $L 300 ff-a /t/plugin-fixed &
sh $L 300 ff-b /t/plugin-fixed &
sh $L 300 ff-c /t/plugin-fixed &
wait
