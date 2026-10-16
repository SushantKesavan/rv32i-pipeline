// Insertion sort of 64 pseudo-random values.
#define N 64
static int a[N];
int main(void) {
  unsigned s = 88172645u;
  for (int i = 0; i < N; i++) { s ^= s << 13; s ^= s >> 17; s ^= s << 5; a[i] = (int)(s & 0x3ff); }
  for (int i = 1; i < N; i++) {
    int key = a[i], j = i - 1;
    while (j >= 0 && a[j] > key) { a[j + 1] = a[j]; j--; }
    a[j + 1] = key;
  }
  for (int i = 0; i < N - 1; i++) if (a[i] > a[i + 1]) return 2;
  return 1;
}
