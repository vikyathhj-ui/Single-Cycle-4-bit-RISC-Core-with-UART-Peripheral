/* irq_test (BRIEF A4): timer and GPIO interrupts, plus checks that riscv-formal does not cover here
   (docs/VERIFICATION.md §2): software interrupt, interrupt priority MEI > MSI > MTI [P §3.1.9],
   ECALL / illegal-instruction traps with mcause, mepc, mtval (SPEC §5.1), and the WARL read-back
   masks of mstatus, mie, mtvec, mepc, mcause, misa (SPEC §3, MICROARCH §8).
   Every line it prints is checked by tb/system/test_irq_test.py. */
#include "hal.h"

static volatile uint32_t n_timer, n_gpio, n_soft, n_exc;
static volatile uint32_t order[4], n_order;
static volatile uint32_t last_cause, last_epc, last_tval;

uint32_t trap_handler(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    if (mcause & MCAUSE_INT) {
        uint32_t code = mcause & 0xF;
        if (n_order < 4) order[n_order++] = code;
        if (code == 7) {                         /* MTI: clear by moving mtimecmp far away */
            n_timer++;
            timer_set_cmp(~0ull);
        } else if (code == 3) {                  /* MSI */
            n_soft++;
            TIMER_MSIP = 0;
        } else if (code == 11) {                 /* MEI from the IRQC */
            if (IRQC_PENDING & (1u << GPIO_IRQ)) {
                GPIO_IRQ_STATUS = GPIO_IRQ_STATUS;   /* W1C every pending pin */
                n_gpio++;
            } else {
                IRQC_ENABLE = 0;                     /* unexpected source: stop it */
            }
        }
        return mepc;                             /* interrupts: resume the interrupted instruction */
    }
    n_exc++;
    last_cause = mcause;
    last_epc = mepc;
    last_tval = mtval;
    return mepc + 4;                             /* exceptions here: skip the instruction */
}

static void csr_masks(void)
{
    uint32_t keep_tvec = csr_read(mtvec);
    csr_clear(mstatus, MSTATUS_MIE);
    csr_write(mstatus, 0xFFFFFFFFu); uint32_t ms = csr_read(mstatus);
    csr_write(mstatus, 0);
    csr_write(mie, 0xFFFFFFFFu);     uint32_t ie = csr_read(mie);
    csr_write(mie, 0);
    csr_write(mtvec, 0xFFFFFFFFu);   uint32_t tv = csr_read(mtvec);
    csr_write(mtvec, keep_tvec);
    csr_write(mepc, 0xFFFFFFFFu);    uint32_t ep = csr_read(mepc);
    csr_write(mcause, 0xFFFFFFFFu);  uint32_t mc = csr_read(mcause);
    csr_write(misa, 0);              uint32_t ma = csr_read(misa);
    lp_printf("CSR mstatus=%08x mie=%08x mtvec=%08x mepc=%08x mcause=%08x misa=%08x\n",
              ms, ie, tv, ep, mc, ma);
}

int main(void)
{
    uart_init(UART_DIV);
    lp_printf("irq_test start\n");
    csr_masks();

    /* --- exceptions: ECALL and an illegal instruction (all-zero word) */
    __asm__ volatile("ecall");
    lp_printf("EXC ecall mcause=%x mtval=%x\n", last_cause, last_tval);
    __asm__ volatile(".word 0x00000000");
    lp_printf("EXC illegal mcause=%x mtval=%x\n", last_cause, last_tval);

    /* --- timer interrupt, three times */
    csr_write(mie, MIE_MTIE);
    csr_set(mstatus, MSTATUS_MIE);
    for (int i = 0; i < 3; i++) {
        uint32_t before = n_timer;
        timer_set_cmp(timer_now() + 500);
        while (n_timer == before) { }
    }
    lp_printf("TIMER count=%u\n", n_timer);

    /* --- software interrupt */
    csr_write(mie, MIE_MSIE);
    TIMER_MSIP = 1;
    while (n_soft == 0) { }
    lp_printf("SOFT count=%u\n", n_soft);

    /* --- priority: make MSI and MTI pending with MIE = 0, then open the gate */
    csr_clear(mstatus, MSTATUS_MIE);
    n_order = 0;
    timer_set_cmp(0);                            /* mtime >= 0: MTIP now */
    TIMER_MSIP = 1;
    csr_write(mie, MIE_MSIE | MIE_MTIE);
    csr_set(mstatus, MSTATUS_MIE);
    while (n_order < 2) { }
    lp_printf("ORDER %u %u\n", order[0], order[1]);

    /* --- GPIO edge interrupt through the IRQC (MEI) */
    csr_write(mie, MIE_MEIE);
    IRQC_ENABLE = 1u << GPIO_IRQ;
    GPIO_RISE_EN = 0x01;
    lp_printf("WAIT GPIO\n");
    while (n_gpio == 0) { }
    lp_printf("GPIO count=%u\n", n_gpio);

    lp_printf("DONE\n");
    uart_flush();
    return 0;
}
