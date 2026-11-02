/* Minimal HAL for lp_rv32 (BRIEF A4): UART, timer, GPIO, IRQC, PMU, SYSCTRL, CSRs.
   Register names come from the generated sw/include/lp_rv32.h (scripts/memmap.yaml). */
#ifndef HAL_H
#define HAL_H
#include <stdint.h>
#include "lp_rv32.h"

#define csr_read(csr) ({ uint32_t v_; __asm__ volatile("csrr %0, " #csr : "=r"(v_)); v_; })
#define csr_write(csr, v) __asm__ volatile("csrw " #csr ", %0" :: "rK"(v))
#define csr_set(csr, v)   __asm__ volatile("csrs " #csr ", %0" :: "rK"(v))
#define csr_clear(csr, v) __asm__ volatile("csrc " #csr ", %0" :: "rK"(v))

#define MSTATUS_MIE (1u << 3)
#define MIE_MSIE    (1u << 3)
#define MIE_MTIE    (1u << 7)
#define MIE_MEIE    (1u << 11)
#define MCAUSE_INT  0x80000000u

/* UART bit period in cycles minus 1; simulation default keeps frames short. */
#ifndef UART_DIV
#define UART_DIV 7
#endif

void     hal_wait_peri(void);           /* wait until the PMU reports PERI ON (D-022) */
void     uart_init(uint32_t div);
void     uart_putc(char c);
void     uart_puts(const char *s);
void     uart_flush(void);                 /* wait until the TX FIFO and shifter are empty */
int      uart_getc(void);                  /* blocking */
void     lp_printf(const char *fmt, ...);  /* %s %c %d %u %x %08x (width + zero pad), %% */

uint64_t timer_now(void);
void     timer_set_cmp(uint64_t cmp);      /* safe 3-write update [P §3.2.1] */

uint64_t rdcycle64(void);
uint64_t rdinstret64(void);

void     pmu_request(uint32_t mode);       /* write MODE_REQ */
void     pmu_wait_idle(void);              /* wait until MODE_STATUS.BUSY = 0 */
void     enter_idle(uint32_t wake_mask);   /* SPEC §8.2: MODE_REQ = IDLE then WFI */
void     enter_deep_sleep(uint32_t wake_mask); /* SPEC §8.3: does not return (warm boot) */

/* Weak default: prints the trap and spins. Return value = new mepc. */
uint32_t trap_handler(uint32_t mcause, uint32_t mepc, uint32_t mtval);
#endif
