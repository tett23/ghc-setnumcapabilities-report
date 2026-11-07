#!/bin/sh
cd /t
LIMIT=80 sh /src/.plughang/caploop.sh 1000 grow-a /t/grow +RTS -N4 -RTS 8 &
LIMIT=80 sh /src/.plughang/caploop.sh 1000 grow-b /t/grow +RTS -N4 -RTS 8 &
LIMIT=80 sh /src/.plughang/caploop.sh 1000 grow-n8 /t/grow +RTS -N8 -RTS 8 &
wait
