// Sieve of Eratosthenes below 512: byte loads/stores, nested loops (97 primes).
static unsigned char flag[512];
volatile int zero;
int main(void) {
  int count = zero;
  for (int i = 2; i < 512; i++)
    if (!flag[i]) { count++; for (int j = i + i; j < 512; j += i) flag[j] = 1; }
  return count == 97 ? 1 : 2;
}
