# make bench   : run all benchmarks under all 5 branch predictors, print tables, write results.csv
# make check   : verify the pipeline's final registers/memory equal the single-cycle core's
# make hex     : rebuild sw/hex/*.hex from sw/*.c (needs a RISC-V compiler; pre-built hex files are included)
# SIM=verilator make bench   (macOS: export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk first)
SIM ?= iverilog

bench:
	python3 scripts/run_bench.py --sim $(SIM)
check:
	python3 scripts/run_bench.py --sim $(SIM) --check
hex:
	./scripts/build_sw.sh
clean:
	rm -rf build results.csv sw/build
