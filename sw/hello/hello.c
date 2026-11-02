/* hello (BRIEF A4): print a greeting and a few identity CSRs / SYSCTRL values over the UART. */
#include "hal.h"

int main(void)
{
    uart_init(UART_DIV);
    lp_printf("Hello from LP-RV32!\n");
    lp_printf("misa=%08x mhartid=%u sysctrl_id=%08x reset_cause=%x\n",
              csr_read(misa), csr_read(mhartid), SYSCTRL_ID, SYSCTRL_RESET_CAUSE);
    lp_printf("DONE\n");
    uart_flush();
    return 0;
}
