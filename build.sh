#!/bin/sh
rm pisc-exp

odin build src -out:pisc-exp -debug

[[ $1 = "run" ]] && ./pisc-exp