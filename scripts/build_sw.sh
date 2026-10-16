#!/usr/bin/env bash
# Build sw/*.c -> sw/hex/*.hex.  Uses riscv64-unknown-elf-gcc / riscv64-elf-gcc if installed,
# otherwise LLVM clang + lld (macOS: `brew install llvm lld`).  Pre-built hex files are already in sw/hex.
set -euo pipefail
cd "$(dirname "$0")/.."
FLAGS="-march=rv32i -mabi=ilp32 -O2 -ffreestanding -fno-builtin -nostdlib"
if   command -v riscv64-unknown-elf-gcc >/dev/null; then CC="riscv64-unknown-elf-gcc $FLAGS"; LD="riscv64-unknown-elf-gcc $FLAGS -Wl,-T,sw/link.ld"; OC=riscv64-unknown-elf-objcopy; MODE=gcc
elif command -v riscv64-elf-gcc         >/dev/null; then CC="riscv64-elf-gcc $FLAGS";         LD="riscv64-elf-gcc $FLAGS -Wl,-T,sw/link.ld";         OC=riscv64-elf-objcopy;         MODE=gcc
else
  CLANG=${CLANG:-$(command -v clang || true)}
  if command -v brew >/dev/null 2>&1 && [ -x "$(brew --prefix llvm 2>/dev/null)/bin/clang" ]; then CLANG="$(brew --prefix llvm)/bin/clang"; fi
  LLBIN=$(dirname "$CLANG")
  CC="$CLANG --target=riscv32 $FLAGS -mno-relax"; LD="$LLBIN/ld.lld --no-relax -T sw/link.ld"
  OC=$(command -v llvm-objcopy || echo "$LLBIN/llvm-objcopy"); MODE=llvm
fi
mkdir -p sw/build sw/hex
benches=${*:-bubble insertion fib_rec fib_iter sieve}
for b in $benches; do
  $CC -c sw/crt0.S -o sw/build/crt0.o
  $CC -c sw/$b.c   -o sw/build/$b.o
  if [ $MODE = gcc ]; then $LD sw/build/crt0.o sw/build/$b.o -o sw/build/$b.elf
  else                     $LD sw/build/crt0.o sw/build/$b.o -o sw/build/$b.elf; fi
  $OC -O binary sw/build/$b.elf sw/build/$b.bin
  python3 scripts/bin2hex.py sw/build/$b.bin sw/hex/$b.hex
  echo "built sw/hex/$b.hex ($(wc -l < sw/hex/$b.hex) words)"
done
