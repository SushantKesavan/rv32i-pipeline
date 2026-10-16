// Iterative Fibonacci repeated 20 times: tight loops with very predictable branches.
volatile unsigned zero, out;            // volatile: stop the compiler folding the whole program away
int main(void) {
  for (int r = 0; r < 20; r++) {
    unsigned a = zero, b = zero + 1;
#pragma GCC unroll 1
    for (int i = 0; i < 40; i++) { unsigned t = a + b; a = b; b = t; }
    out = out + a;                      // F(40) = 102334155 each time
  }
  return out == 20u * 102334155u ? 1 : 2;
}
