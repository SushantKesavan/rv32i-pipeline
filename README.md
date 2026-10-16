# 5-stage pipelined RV32I core

IF -> ID -> EX -> MEM -> WB, written in SystemVerilog around the modules from your single-cycle core
(`alu`, `imm_gen`, `control`, `regfile`, `imem`/`dmem`).

## Run it
```
brew install icarus-verilog          # (or verilator)
make check                           # pipeline == single-cycle reference on every benchmark?
make bench                           # CPI + prediction accuracy for every predictor x benchmark
```
No RISC-V compiler needed: the compiled benchmarks are in `sw/hex/`. To rebuild them: `brew install llvm lld`, `make hex`.

## Hazard handling (`rtl/rv32i_pipe.sv`)
| hazard | handling | cost |
|---|---|---|
| RAW, ALU result | forward EX/MEM -> EX and MEM/WB -> EX; regfile write-through for WB -> ID | 0 |
| load-use | stall 1 cycle (bubble into EX, hold PC and IF/ID) | 1 |
| JAL | redirect from ID | 1 |
| conditional branch | predicted in ID; predicted-taken redirects from ID (1 bubble); resolved in EX, wrong => flush IF+ID | 0 / 1 / 2 |
| JALR | resolved in EX | 2 |
| ECALL | stops fetch; `halt` when it retires in WB | - |

## Branch predictors (`rtl/bpred.sv`, `PRED` parameter)
0 static not-taken, 1 static backward-taken/forward-not-taken, 2 1-bit (64 entries, PC-indexed),
3 2-bit saturating (bimodal, 64 entries), 4 GShare (64 x 2-bit counters, index = PC[7:2] ^ 6-bit global history).
History is updated speculatively at prediction and repaired from a snapshot on a misprediction.
There is no BTB: the target is computed in ID, which is why a correctly predicted taken branch still costs 1 cycle.

## Measuring
`tb/tb_pipe.sv` prints one RESULT line: cycles, retired instructions, CPI, conditional branches, mispredicts,
accuracy (conditional branches only; JAL/JALR excluded), plus stall/flush counts. `scripts/run_bench.py` checks that
cycles == instrs + 3 + load-use stalls + ID redirects + 2*EX redirects - (mispredicted predicted-taken), i.e. the counters
account for every lost cycle.

## Limits
* Benchmarks may only use zero-initialised globals (dmem is not preloaded) and no mul/div (RV32I).
* Memory is the idealised 1-cycle async memory from the original design; there is no cache or memory latency.
* No Basys 3 / Vivado flow is included, so no Fmax or LUT numbers come from this project.
