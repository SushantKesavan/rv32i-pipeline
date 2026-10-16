# Self-checking RV32I test. On success: gp (x3) = 1.  On failure: gp = failing test number (>= 2).
.macro CHECK reg, val, n
  li   t6, \val
  li   gp, \n
  bne  \reg, t6, fail
.endm

.section .text
.globl _start
_start:
  # ---- register-register / immediate ALU ----
  li   a0, 5
  li   a1, -3
  add  a2, a0, a1
  CHECK a2, 2, 2
  sub  a2, a0, a1
  CHECK a2, 8, 3
  and  a2, a0, a1
  CHECK a2, 5, 4
  or   a2, a0, a1
  CHECK a2, -3, 5
  xor  a2, a0, a1
  CHECK a2, -8, 6
  slt  a2, a1, a0
  CHECK a2, 1, 7
  sltu a2, a1, a0
  CHECK a2, 0, 8
  slli a2, a0, 4
  CHECK a2, 80, 9
  srli a2, a1, 28
  CHECK a2, 15, 10
  srai a2, a1, 1
  CHECK a2, -2, 11
  sll  a2, a0, a0
  CHECK a2, 160, 12
  lui  a2, 0x12345
  CHECK a2, 0x12345000, 13
  auipc a2, 0
  auipc a3, 0
  sub  a4, a3, a2
  CHECK a4, 4, 14
  addi x0, x0, 5            # writes to x0 must be ignored
  CHECK x0, 0, 15

  # ---- loads / stores ----
  li   s0, 0x100
  li   a0, 0x80F1F2F3
  sw   a0, 0(s0)
  lw   a2, 0(s0)
  CHECK a2, 0x80F1F2F3, 16
  lb   a2, 0(s0)
  CHECK a2, 0xFFFFFFF3, 17
  lbu  a2, 1(s0)
  CHECK a2, 0xF2, 18
  lh   a2, 2(s0)
  CHECK a2, 0xFFFF80F1, 19
  lhu  a2, 2(s0)
  CHECK a2, 0x80F1, 20
  li   a3, 0xAA
  sb   a3, 1(s0)
  lw   a2, 0(s0)
  CHECK a2, 0x80F1AAF3, 21
  li   a3, 0x1234
  sh   a3, 2(s0)
  lw   a2, 0(s0)
  CHECK a2, 0x1234AAF3, 22

  # ---- branches (a0=5, a1=-3) ----
  li   a0, 5
  li   a1, -3
  li   a4, 0
  beq  a0, a1, 1f           # not taken
  addi a4, a4, 1
1:
  bne  a0, a1, 2f           # taken
  addi a4, a4, 2
2:
  blt  a1, a0, 3f           # taken (signed)
  addi a4, a4, 4
3:
  bltu a1, a0, 4f           # not taken (unsigned)
  addi a4, a4, 8
4:
  bge  a0, a1, 5f           # taken (signed)
  addi a4, a4, 16
5:
  bgeu a1, a0, 6f           # taken (unsigned)
  addi a4, a4, 32
6:
  CHECK a4, 9, 23

  # ---- jal / jalr ----
  li   a4, 0
  jal  ra, func
  addi a4, a4, 1
  CHECK a4, 11, 24

  # ---- loop: sum 1..10 ----
  li   a0, 0
  li   a1, 10
loop:
  add  a0, a0, a1
  addi a1, a1, -1
  bnez a1, loop
  CHECK a0, 55, 25

  li   gp, 1
  ecall

func:
  addi a4, a4, 10
  ret

fail:
  ecall
