// Recursive Fibonacci: call/return heavy (JAL/JALR), stack traffic, short data-dependent branches.
volatile int zero;                      // defeats constant folding
__attribute__((noinline)) static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
int main(void) { return fib(15 + zero) == 610 ? 1 : 2; }
