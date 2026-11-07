#!/bin/sh
# exp.sh BIN N : experiments with correct tasty patterns (substring patterns)
B=$1; N=$2
cd /w/modules/golem-plugin
L=/src/.plughang/caploop3.sh
echo "noconc: $("$B" -p '!/many threads/' -l | wc -l) tests"
echo "nonet: $("$B" -p '!/ADR 0002/ && !/TLS root/' -l | wc -l) tests"
echo "netonly: $("$B" -p '/ADR 0002/ || /TLS root/' -l | wc -l) tests"
echo "all: $("$B" -l | wc -l) tests"
[ "$N" = 0 ] && exit 0
sh $L "$N" e-noconc "$B" -p '!/many threads/' &
sh $L "$N" e-nonet "$B" -p '!/ADR 0002/ && !/TLS root/' &
sh $L "$N" e-netonly "$B" -p '/ADR 0002/ || /TLS root/' &
wait
