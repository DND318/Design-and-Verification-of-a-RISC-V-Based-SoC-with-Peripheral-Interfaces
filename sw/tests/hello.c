/* Walking skeleton: print a greeting over the UART at 115200 baud (50 MHz).
   The simulation testbench ends the run when it reads the "@@PASS" line. */
#include "soc.h"

int main(void)
{
    uart_init(433);
    uart_puts("Hello from RISC-V SoC!\n");
    uart_puts("@@PASS\n");
    uart_flush();
    return 0;
}
