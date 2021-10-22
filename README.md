## A Game-ish assembly language enviroment

### Instruction Set

```as
load  r r[i]
store r r[i]
mov   r r/i

add r r/i
sub r r/i
mul r r/i
div r r/i

or  r r/i
and r r/i
not r
xor r r/i

sl  r r/i
srl r r/i
sra r r/i

ceq r r/i
cgt r r/i
clt r r/i

jmp  r/i
jt   r/i
jf   r/i

pokev r
peekv r

call r/i
ret

:LABEL
```
