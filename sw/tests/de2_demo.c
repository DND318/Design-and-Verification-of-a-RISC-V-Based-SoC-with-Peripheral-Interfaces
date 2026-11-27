/* DE2-115 board demo ("sensor node" flow).
   - Timer interrupt at 10 Hz: an 8-bit counter on LEDG[7:0].
   - SW[7] = 1: LEDG shows SW[6:0] instead of the counter.
   - GPIO rising edge on SW[6:0] -> IRQ controller -> MEI: prints "SW<n> up".
   - I2C: write/read 4 bytes in the on-board 24LC32A EEPROM (address 0x50).
   - SPI: SD card in SPI mode, CMD0 (expect R1 = 0x01) and CMD8.
   - UART 115200 8N1: echo, and single-key commands (h, e, s, t).
   Terminal: 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control. */
#include "soc.h"

#define TICK_HZ       10u
#define TICK_CYCLES   (CLK_HZ / TICK_HZ)

static volatile uint32_t ticks;

static void put_byte(uint8_t b)
{
    const char *hx = "0123456789ABCDEF";
    uart_putc(hx[b >> 4]);
    uart_putc(hx[b & 0xF]);
}
static volatile uint32_t sw_events;

/* ---------------- 64-bit timer helpers ---------------- */
static uint64_t timer_now(void)
{
    uint32_t hi, lo;
    do {
        hi = TIMER_TDR1;
        lo = TIMER_TDR0;
    } while (hi != TIMER_TDR1);
    return ((uint64_t)hi << 32) | lo;
}

static void timer_set_cmp(uint64_t t)
{
    TIMER_TCMP1 = 0xFFFFFFFFu;              /* avoid a spurious match while updating */
    TIMER_TCMP0 = (uint32_t)t;
    TIMER_TCMP1 = (uint32_t)(t >> 32);
}

static void delay_ms(uint32_t ms)
{
    uint64_t end = timer_now() + (uint64_t)ms * (CLK_HZ / 1000u);
    while (timer_now() < end)
        ;
}

/* ---------------- trap handler (called from crt0.S) ---------------- */
uint32_t trap_handler(uint32_t mcause, uint32_t mepc)
{
    if (mcause == MCAUSE_MTI) {
        uint64_t cmp = ((uint64_t)TIMER_TCMP1 << 32) | TIMER_TCMP0;
        timer_set_cmp(cmp + TICK_CYCLES);
        ticks++;
        uint32_t sw = GPIO_IN;
        GPIO_OUT = (sw & 0x80u) ? (sw & 0x7Fu) : (ticks & 0xFFu);
        return mepc;
    }
    if (mcause == MCAUSE_MEI) {
        if (IRQC_ID == 4) {                 /* GPIO */
            sw_events |= GPIO_IS;
            GPIO_IS = 0xFF;
        }
        return mepc;
    }
    uart_puts("\n!! exception mcause=");
    uart_puthex(mcause);
    uart_puts(" mepc=");
    uart_puthex(mepc);
    uart_puts("\n");
    return mepc + 4;
}

/* ---------------- I2C EEPROM (24LC32A, 32 Kbit, 2-byte address) ---------------- */
#define EE_WR   0xA0u
#define EE_RD   0xA1u

static uint32_t i2c_cmd(uint32_t cmd)
{
    I2C_CMD = cmd;
    while (!(I2C_ISR & 1u))
        ;
    I2C_ISR = 0x3u;
    return I2C_STATUS & I2C_ST_RX_NACK;
}

static uint32_t i2c_write(uint8_t b, uint32_t flags)
{
    I2C_TXDATA = b;
    return i2c_cmd(I2C_CMD_WRITE | flags);
}

static uint8_t i2c_read(uint32_t flags)
{
    i2c_cmd(I2C_CMD_READ | flags);
    return (uint8_t)I2C_RXDATA;
}

static int eeprom_wait_ready(void)
{
    for (int i = 0; i < 200; i++) {          /* write cycle is at most 5 ms */
        if (i2c_write(EE_WR, I2C_CMD_START) == 0) {
            i2c_cmd(I2C_CMD_STOP);
            return 0;
        }
    }
    i2c_cmd(I2C_CMD_STOP);
    return -1;
}

static void eeprom_test(void)
{
    const uint16_t addr = 0x0FF0;            /* last page, away from any user data */
    uint8_t wr[4] = {0xC0, 0xFF, 0xEE, (uint8_t)ticks};
    uint8_t rd[4];

    uart_puts("EEPROM @0x50: ");
    I2C_CTRL = 1;
    if (i2c_write(EE_WR, I2C_CMD_START)) {
        i2c_cmd(I2C_CMD_STOP);
        uart_puts("no ACK on address, FAIL\n");
        return;
    }
    uint32_t nack = i2c_write((uint8_t)(addr >> 8), 0);
    nack |= i2c_write((uint8_t)addr, 0);
    for (int i = 0; i < 4; i++)
        nack |= i2c_write(wr[i], (i == 3) ? I2C_CMD_STOP : 0);
    if (nack || eeprom_wait_ready()) {
        uart_puts("write NACK/timeout, FAIL\n");
        return;
    }
    nack = i2c_write(EE_WR, I2C_CMD_START);
    nack |= i2c_write((uint8_t)(addr >> 8), 0);
    nack |= i2c_write((uint8_t)addr, 0);
    nack |= i2c_write(EE_RD, I2C_CMD_START);
    for (int i = 0; i < 4; i++)
        rd[i] = i2c_read((i == 3) ? (I2C_CMD_NACK | I2C_CMD_STOP) : 0);

    int ok = (nack == 0);
    for (int i = 0; i < 4; i++) {
        ok &= (rd[i] == wr[i]);
        put_byte(rd[i]);
        uart_putc(' ');
    }
    uart_puts(ok ? "PASS\n" : "FAIL\n");
}

/* ---------------- SD card in SPI mode ---------------- */
static uint8_t spi_xfer(uint8_t b)
{
    SPI_TXDATA = b;
    while (SPI_STATUS & SPI_ST_RX_EMPTY)
        ;
    return (uint8_t)SPI_RXDATA;
}

static uint8_t sd_cmd(uint8_t cmd, uint32_t arg, uint8_t crc)
{
    spi_xfer(0xFF);
    spi_xfer(0x40u | cmd);
    spi_xfer((uint8_t)(arg >> 24));
    spi_xfer((uint8_t)(arg >> 16));
    spi_xfer((uint8_t)(arg >> 8));
    spi_xfer((uint8_t)arg);
    spi_xfer(crc);
    uint8_t r = 0xFF;
    for (int i = 0; i < 10 && r == 0xFF; i++)  /* NCR: up to 8 bytes */
        r = spi_xfer(0xFF);
    return r;
}

static void sd_test(void)
{
    SPI_CTRL = 0;
    SPI_CLKDIV = 63;                          /* 50 MHz / (2 x 64) = 390 kHz, below 400 kHz */
    SPI_CTRL = 1;                             /* mode 0, MSB first */
    SPI_CS = 1;
    for (int i = 0; i < 10; i++)              /* >= 74 clocks with CS high */
        spi_xfer(0xFF);

    SPI_CS = 0;
    uint8_t r1 = sd_cmd(0, 0, 0x95);          /* GO_IDLE_STATE */
    uart_puts("SD CMD0  R1=");
    put_byte(r1);
    if (r1 == 0xFF) {
        uart_puts("  (no card)\n");
    } else {
        uart_puts(r1 == 0x01 ? "  idle, PASS\n" : "  unexpected\n");
        if (r1 == 0x01) {
            r1 = sd_cmd(8, 0x1AA, 0x87);      /* SEND_IF_COND, 2.7-3.6 V, check pattern 0xAA */
            uint32_t r7 = 0;
            for (int i = 0; i < 4; i++)
                r7 = (r7 << 8) | spi_xfer(0xFF);
            uart_puts("SD CMD8  R1=");
            put_byte(r1);
            uart_puts(" R7=");
            uart_puthex(r7);
            uart_puts((r1 == 0x01 && (r7 & 0xFFFu) == 0x1AAu) ? "  SDv2\n" : "  SDv1/MMC or no CMD8\n");
        }
    }
    SPI_CS = 1;
    spi_xfer(0xFF);
    SPI_CTRL = 0;
}

static void help(void)
{
    uart_puts("keys: h help, e EEPROM test, s SD test, t ticks; other keys echo\n"
              "SW[7]=1 shows SW[6:0] on LEDG, SW[6:0] rising edge prints a message\n");
}

int main(void)
{
    uart_init(433);                           /* 115200 baud at 50 MHz */
    uart_puts("\n=== RISC-V SoC on DE2-115 ===\n");
    help();

    GPIO_OUT = 0;
    GPIO_OE = 0xFF;
    GPIO_IS = 0xFF;
    GPIO_IE = 0x7F;
    IRQC_ENABLE = 1u << 3;                    /* GPIO source */

    TIMER_TCR = 0;
    TIMER_TDR1 = 0;
    TIMER_TDR0 = 0;
    timer_set_cmp(TICK_CYCLES);
    TIMER_TIER = 1;
    TIMER_TCR = 1;                            /* count every clock */

    csr_set(mie, MIE_MTIE | MIE_MEIE);
    csr_set(mstatus, MSTATUS_MIE);

    delay_ms(10);
    eeprom_test();
    sd_test();

    for (;;) {
        if (sw_events) {
            csr_clear(mstatus, MSTATUS_MIE);
            uint32_t ev = sw_events;
            sw_events = 0;
            csr_set(mstatus, MSTATUS_MIE);
            for (uint32_t n = 0; n < 7; n++) {
                if (ev & (1u << n)) {
                    uart_puts("SW");
                    uart_putc((char)('0' + n));
                    uart_puts(" up\n");
                }
            }
        }
        if (!(UART_STATUS & UART_ST_RX_EMPTY)) {
            char c = (char)UART_RXDATA;
            switch (c) {
            case 'h': help(); break;
            case 'e': eeprom_test(); break;
            case 's': sd_test(); break;
            case 't': uart_puts("ticks="); uart_putdec(ticks); uart_puts("\n"); break;
            case '\r': uart_puts("\n"); break;
            default: uart_putc(c); break;
            }
        }
    }
}
