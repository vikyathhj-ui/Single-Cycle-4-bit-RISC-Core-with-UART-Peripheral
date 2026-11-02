/* loader_payload: program sent to the boot ROM's UART loader by the loader system test
   (tb/system/test_loader.py). Proves the loaded image runs: prints a marker and its boot state. */
#include "hal.h"

int main(void)
{
    uart_init(UART_DIV);
    lp_printf("LOADED OK boot_sel=%u reset_cause=%x\n", SYSCTRL_BOOT, SYSCTRL_RESET_CAUSE);
    uart_flush();
    return 0;
}
