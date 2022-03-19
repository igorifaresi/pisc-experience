#!/bin/sh

rm build/pisc-exp_linux_x64
rm build/pisc-exp_windows_x64

odin build src -opt:2 -out:build/pisc-exp_linux_x64       -target:linux_amd64   -debug
odin build src -opt:2 -out:build/pisc-exp_windows_x64.exe -target:windows_amd64 -debug

[[ $1 = "run"   ]] && ./build/pisc-exp_linux_x64

[[ $1 = "debug" ]] && gf2 ./build/pisc-exp_linux_x64