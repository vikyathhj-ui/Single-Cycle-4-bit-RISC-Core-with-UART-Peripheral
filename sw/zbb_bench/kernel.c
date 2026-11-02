/* zbb_bench kernel (BRIEF A4 "the same algorithm with and without Zbb"). This one file is compiled
   twice by scripts/build_sw.py: with -march=rv32i_zicsr (SUFFIX=_base, GCC uses libgcc / shift
   sequences) and with -march=rv32i_zicsr_zbb (SUFFIX=_zbb, GCC emits cpop, clz, ctz, rev8, rol,
   min, max, andn, orc.b...). Both must return the same value.
   The kernel: for every word of the input, population count, count leading / trailing zeros,
   byte reversal, rotation, min/max and and-not, folded into one checksum. */
#include <stdint.h>

#define CAT(a, b) a##b
#define NAME(a, b) CAT(a, b)

uint32_t NAME(bitkernel, SUFFIX)(const uint32_t *v, int n)
{
    uint32_t acc = 0, lo = 0xFFFFFFFFu, hi = 0;
    for (int i = 0; i < n; i++) {
        uint32_t x = v[i];
        acc += (uint32_t)__builtin_popcount(x);
        acc += (uint32_t)__builtin_clz(x | 1u);
        acc += (uint32_t)__builtin_ctz(x | 0x80000000u);
        acc ^= __builtin_bswap32(x);
        acc = (acc << 5) | (acc >> 27);
        lo = x < lo ? x : lo;
        hi = x > hi ? x : hi;
        acc += x & ~hi;
    }
    return acc ^ lo ^ hi;
}
