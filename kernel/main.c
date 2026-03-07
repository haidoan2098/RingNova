/* ===========================================================
 * kernel/main.c — Kernel C entry point
 *
 * Called from boot/arch/start.S after:
 *   - Exception-mode stacks are set up
 *   - BSS is zeroed
 *   - MMU is OFF (physical addresses only)
 *
 * Purpose at this stage: verify UART output works.
 *   Next phase will add exception vector table, then MMU.
 * =========================================================== */

#include "../bsp/drivers/uart/uart.h"

void kmain(void)
{
    uart_init();

    uart_puts("\r\n");
    uart_puts("================================================\r\n");
    uart_puts("  RefixOS — ARMv7-A bare-metal kernel\r\n");
    uart_puts("  Boot OK — UART online\r\n");
    uart_puts("================================================\r\n");

    /* Halt — scheduler not implemented yet */
    for (;;)
        ;
}
