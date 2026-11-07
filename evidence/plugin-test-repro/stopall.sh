#!/bin/sh
# stops every loop in the container
pkill -f plugrun
pkill -f caploop
pkill -f golem-plugin-test
pkill -f setcaps
sleep 1
ps -eo pid,args | grep -E "caploop|plugrun|golem-plugin-test|setcaps" | grep -v grep | wc -l
