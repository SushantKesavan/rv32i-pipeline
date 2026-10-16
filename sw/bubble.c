// Bubble sort of 64 pseudo-random values (xorshift, no multiply). Data-dependent compare branch.
#define N 64
static int a[N];
int main(void) {
  unsigned s = 2463534242u;
  for (int i = 0; i < N; i++) { s ^= s << 13; s ^= s >> 17; s ^= s << 5; a[i] = (int)(s & 0x3ff); }
  for (int i = 0; i < N - 1; i++)
    for (int j = 0; j < N - 1 - i; j++)
      if (a[j] > a[j + 1]) { int t = a[j]; a[j] = a[j + 1]; a[j + 1] = t; }
  for (int i = 0; i < N - 1; i++) if (a[i] > a[i + 1]) return 2;
  return 1;
}
