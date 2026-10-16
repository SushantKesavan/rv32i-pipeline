# Minimal startup: stack at 0x5000 (top of the 4 KB dmem window), call main,
# report main's return value in x3 (1 = PASS, anything else = FAIL) and halt with ECALL.
    .section .text.init
    .globl _start
_start:
    lui   sp, 0x5
    call  main
    mv    gp, a0
    ecall
1:  j     1b
