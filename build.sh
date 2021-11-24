#!/bin/sh
rm pisc-exp

odin build src -out:pisc-exp -opt:2 -debug

[[ $1 = "run"   ]] && ./pisc-exp

[[ $1 = "debug" ]] && gf2 ./pisc-exp