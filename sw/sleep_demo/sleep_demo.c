/* sleep_demo (BRIEF A4, A3 "Power integration"; SPEC §8):
   cold boot -> IDLE, woken by the timer (prints mcycle and mtime deltas: mcycle stops while the
   CORE clock is gated, mtime keeps counting in AON) -> DEEP_SLEEP, woken by a UART start bit ->
   warm boot (prints the wake reason from SYSCTRL) -> DEEP_SLEEP, woken by the timer -> warm boot ->
   DONE. The stage is kept in SYSCTRL.SCRATCH (AON); a marker in DMEM .noinit shows that MEM keeps
   its contents across DEEP_SLEEP. Checked by tb/system/test_sleep_demo.py. */
#include "hal.h"

#define MARKER 0xCAFEF00Du
__attribute__((section(".noinit"))) static volatile uint32_t mem_marker;
static volatile uint32_t n_timer;

uint32_t trap_handler(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    (void)mtval;
    if (mcause == (MCAUSE_INT | 7)) {
        n_timer++;
        timer_set_cmp(~0ull);
        return mepc;
    }
    lp_printf("TRAP mcause=%08x mepc=%08x\n", mcause, mepc);
    for (;;) { }
}

static void deep_sleep_until(uint32_t stage, uint32_t wake_bit)
{
    SYSCTRL_SCRATCH = stage;
    SYSCTRL_WAKE_SRC = 0x7;                       /* W1C: start with no recorded source */
    lp_printf("DEEP%u enter\n", stage);
    enter_deep_sleep(wake_bit);                    /* does not return: the next run is a warm boot */
}

int main(void)
{
    uart_init(UART_DIV);
    uint32_t cause = SYSCTRL_RESET_CAUSE;
    SYSCTRL_RESET_CAUSE = cause;                   /* W1C */

    if (!(cause & SYSCTRL_RESET_CAUSE_WARM_MASK)) {
        lp_printf("COLD reset_cause=%x\n", cause);
        mem_marker = MARKER;

        /* IDLE, woken by the machine timer through the core interrupt (wake_irq[0]) */
        csr_write(mie, MIE_MTIE);
        csr_set(mstatus, MSTATUS_MIE);
        uart_flush();
        uint64_t c0 = rdcycle64(), t0 = timer_now();
        timer_set_cmp(t0 + 3000);
        enter_idle(1u << 0);
        uint64_t c1 = rdcycle64(), t1 = timer_now();
        lp_printf("IDLE woke timer_irqs=%u mcycle_delta=%u mtime_delta=%u wake_src=%x\n", n_timer,
                  (uint32_t)(c1 - c0), (uint32_t)(t1 - t0), SYSCTRL_WAKE_SRC);

        /* DEEP_SLEEP 1: woken by a UART RX start bit (AON detector, wake_irq[1]) */
        csr_clear(mstatus, MSTATUS_MIE);
        SYSCTRL_UART_WAKE_EN = 1;
        deep_sleep_until(1, 1u << 1);
    }

    uint32_t stage = SYSCTRL_SCRATCH;
    uint32_t src = SYSCTRL_WAKE_SRC;
    lp_printf("WARM stage=%u wake_src=%x marker=%08x\n", stage, src, mem_marker);
    if (stage == 1) {
        /* DEEP_SLEEP 2: woken by mtime >= mtimecmp (AON timer, wake_irq[2]) */
        SYSCTRL_UART_WAKE_EN = 0;
        timer_set_cmp(timer_now() + 5000);
        deep_sleep_until(2, 1u << 2);
    }
    lp_printf("DONE\n");
    uart_flush();
    return 0;
}
