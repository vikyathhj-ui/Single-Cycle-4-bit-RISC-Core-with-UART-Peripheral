/* zbb_bench (BRIEF A4): the same kernel (kernel.c) built without and with Zbb; prints the cycle and
   instruction counts of each (mcycle / minstret around the call) and checks the results match.
   Data: 256 words from a fixed xorshift sequence. Checked by tb/system/test_zbb_bench.py. */
#include "hal.h"

uint32_t bitkernel_base(const uint32_t *v, int n);
uint32_t bitkernel_zbb(const uint32_t *v, int n);

#define N 256
static uint32_t data[N];

int main(void)
{
    uart_init(UART_DIV);
    uint32_t s = 0x12345678u;
    for (int i = 0; i < N; i++) {
        s ^= s << 13; s ^= s >> 17; s ^= s << 5;
        data[i] = s;
    }
    uint64_t c0 = rdcycle64(), i0 = rdinstret64();
    uint32_t r_base = bitkernel_base(data, N);
    uint64_t c1 = rdcycle64(), i1 = rdinstret64();
    uint32_t r_zbb = bitkernel_zbb(data, N);
    uint64_t c2 = rdcycle64(), i2 = rdinstret64();
    lp_printf("BASE result=%08x cycles=%u instret=%u\n", r_base, (uint32_t)(c1 - c0), (uint32_t)(i1 - i0));
    lp_printf("ZBB  result=%08x cycles=%u instret=%u\n", r_zbb, (uint32_t)(c2 - c1), (uint32_t)(i2 - i1));
    lp_printf("%s\n", r_base == r_zbb ? "MATCH" : "MISMATCH");
    lp_printf("DONE\n");
    uart_flush();
    return 0;
}
