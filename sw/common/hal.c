/* HAL implementation (see hal.h). */
#include <stdarg.h>
#include "hal.h"

/* The PMU powers the domains up one at a time (CPU, DSP, PERI), so the core runs before PERI is on.
   While PERI is isolated, every UART/GPIO access gets an error response (D-021), so crt0 waits
   here before main() (D-022). */
void hal_wait_peri(void)
{
    for (;;) {
        uint32_t s = PMU_PD_STATE;
        if (((s & PMU_PD_STATE_PERI_STATE_MASK) >> PMU_PD_STATE_PERI_STATE_SHIFT) == PMU_PD_STATE_ON &&
            !(s & PMU_PD_STATE_PERI_BUSY_MASK))
            return;
    }
}

void uart_init(uint32_t div)
{
    UART_BAUD_DIV = div;
    UART_CTRL = UART_CTRL_TX_EN_MASK | UART_CTRL_RX_EN_MASK;
}

void uart_putc(char c)
{
    while (UART_STATUS & UART_STATUS_TX_FULL_MASK) { }
    UART_DATA = (uint8_t)c;
}

void uart_puts(const char *s)
{
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

void uart_flush(void)
{
    while (!(UART_STATUS & UART_STATUS_TX_EMPTY_MASK)) { }
}

int uart_getc(void)
{
    while (UART_STATUS & UART_STATUS_RX_EMPTY_MASK) { }
    return (int)(UART_DATA & 0xFF);
}

static void put_num(uint32_t v, unsigned base, int width, char pad, int neg)
{
    char buf[12];
    int n = 0;
    do {
        uint32_t d = v % base;
        buf[n++] = (char)(d < 10 ? '0' + d : 'a' + d - 10);
        v /= base;
    } while (v);
    if (neg) buf[n++] = '-';
    while (n < width) { uart_putc(pad); width--; }
    while (n) uart_putc(buf[--n]);
}

void lp_printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    for (; *fmt; fmt++) {
        if (*fmt != '%') {
            if (*fmt == '\n') uart_putc('\r');
            uart_putc(*fmt);
            continue;
        }
        fmt++;
        char pad = ' ';
        int width = 0;
        if (*fmt == '0') { pad = '0'; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
        switch (*fmt) {
        case 's': uart_puts(va_arg(ap, const char *)); break;
        case 'c': uart_putc((char)va_arg(ap, int)); break;
        case 'u': put_num(va_arg(ap, uint32_t), 10, width, pad, 0); break;
        case 'x': put_num(va_arg(ap, uint32_t), 16, width, pad, 0); break;
        case 'd': {
            int32_t v = va_arg(ap, int32_t);
            put_num(v < 0 ? (uint32_t)-v : (uint32_t)v, 10, width, pad, v < 0);
            break;
        }
        case '%': uart_putc('%'); break;
        default: break;
        }
    }
    va_end(ap);
}

uint64_t timer_now(void)
{
    uint32_t hi, lo;
    do {
        hi = TIMER_MTIME_HI;
        lo = TIMER_MTIME_LO;
    } while (hi != TIMER_MTIME_HI);
    return ((uint64_t)hi << 32) | lo;
}

void timer_set_cmp(uint64_t cmp)
{
    TIMER_MTIMECMP_HI = 0xFFFFFFFFu;
    TIMER_MTIMECMP_LO = (uint32_t)cmp;
    TIMER_MTIMECMP_HI = (uint32_t)(cmp >> 32);
}

uint64_t rdcycle64(void)
{
    uint32_t hi, lo;
    do {
        hi = csr_read(mcycleh);
        lo = csr_read(mcycle);
    } while (hi != csr_read(mcycleh));
    return ((uint64_t)hi << 32) | lo;
}

uint64_t rdinstret64(void)
{
    uint32_t hi, lo;
    do {
        hi = csr_read(minstreth);
        lo = csr_read(minstret);
    } while (hi != csr_read(minstreth));
    return ((uint64_t)hi << 32) | lo;
}

void pmu_request(uint32_t mode)
{
    PMU_MODE_REQ = mode;
}

void pmu_wait_idle(void)
{
    while (PMU_MODE_STATUS & PMU_MODE_STATUS_BUSY_MASK) { }
}

/* SPEC §8.2: the WFI follows the MODE_REQ write in straight-line code; the core accepts the
   PMU's Q-Channel request once WFI is stalled with the pipeline empty. */
void enter_idle(uint32_t wake_mask)
{
    PMU_WAKE_MODE = PMU_MODE_RUN;
    PMU_WAKE_MASK = ~wake_mask & 0xFFu;
    PMU_MODE_REQ = PMU_MODE_IDLE;
    __asm__ volatile("wfi");
    /* After a wake the PMU has already set MODE_REQ = WAKE_MODE. If the core denied the request
       (an interrupt was already pending), MODE_REQ is still IDLE: put it back to RUN. */
    PMU_MODE_REQ = PMU_MODE_RUN;
}

void enter_deep_sleep(uint32_t wake_mask)
{
    uart_flush();                          /* PERI powers off: let the TX FIFO drain (SPEC §8.3) */
    PMU_WAKE_MODE = PMU_MODE_RUN;
    PMU_WAKE_MASK = ~wake_mask & 0xFFu;
    PMU_MODE_REQ = PMU_MODE_DEEP_SLEEP;
    for (;;) __asm__ volatile("wfi");
}

__attribute__((weak)) uint32_t trap_handler(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    lp_printf("TRAP mcause=%08x mepc=%08x mtval=%08x\n", mcause, mepc, mtval);
    for (;;) { }
    return mepc;
}
