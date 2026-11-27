/* Self-checking SoC test for simulation (tb_soc_top board models:
   SPI MOSI->MISO loopback, GPIO outputs looped to inputs, 24LC32A EEPROM
   at I2C address 0x50). Covers reset values, UART loopback, SPI, GPIO edge
   interrupt through the IRQ controller (MEI), timer interrupt (MTI), I2C
   EEPROM write/read, NACK, and a bus error trap. Prints "@@PASS" or
   "@@FAIL <test>" at the end. */
#include "soc.h"

static volatile uint32_t n_mti, n_mei, n_exc, last_cause, last_irq_id;
static uint32_t fails;

uint32_t trap_handler(uint32_t mcause, uint32_t mepc)
{
    last_cause = mcause;
    if (mcause == MCAUSE_MTI) {
        n_mti++;
        TIMER_TCMP1 = 0xFFFFFFFFu;          /* no further match */
        TIMER_TCMP0 = 0xFFFFFFFFu;
        return mepc;
    }
    if (mcause == MCAUSE_MEI) {
        n_mei++;
        last_irq_id = IRQC_ID;
        GPIO_IS = 0xFF;                     /* W1C: clear the source */
        return mepc;
    }
    n_exc++;
    return mepc + 4;                        /* skip the faulting instruction */
}

static void check(int ok, const char *name)
{
    uart_puts(ok ? "  ok   " : "  FAIL ");
    uart_puts(name);
    uart_puts("\n");
    if (!ok)
        fails++;
}

/* ---------------- I2C helpers ---------------- */
static uint32_t i2c_cmd(uint32_t cmd)
{
    I2C_CMD = cmd;
    while (!(I2C_ISR & 1u))                 /* ISR.done */
        ;
    I2C_ISR = 1u;
    return I2C_STATUS & I2C_ST_RX_NACK;     /* 0 = ACK */
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

static void eeprom_wait_ready(void)
{
    /* ACK polling: the device NACKs its address during the write cycle */
    for (int i = 0; i < 1000; i++) {
        if (i2c_write(0xA0, I2C_CMD_START) == 0) {
            i2c_cmd(I2C_CMD_STOP);
            return;
        }
    }
}

/* ---------------- SPI helper ---------------- */
static uint8_t spi_xfer(uint8_t b)
{
    SPI_TXDATA = b;
    while (SPI_STATUS & SPI_ST_RX_EMPTY)
        ;
    return (uint8_t)SPI_RXDATA;
}

int main(void)
{
    uart_init(433);
    uart_puts("periph test\n");

    /* 1. reset values (doc/spec register tables) */
    check(UART_BAUD == 433 && SPI_CLKDIV == 1 && SPI_CS == 1 && I2C_PRESCALE == 124 &&
          TIMER_TCR == 0x100 && TIMER_TCMP0 == 0xFFFFFFFFu && TIMER_TCMP1 == 0xFFFFFFFFu &&
          IRQC_ENABLE == 0 && GPIO_OE == 0 && csr_read(misa) == 0x40001100u,
          "reset values");

    /* 2. UART internal loopback */
    uart_flush();
    UART_CTRL = UART_CTRL_TX_EN | UART_CTRL_RX_EN | (1u << 5);
    UART_TXDATA = 'Z';
    while (UART_STATUS & UART_ST_RX_EMPTY)
        ;
    uint32_t rx = UART_RXDATA;
    UART_CTRL = UART_CTRL_TX_EN | UART_CTRL_RX_EN;
    check(rx == 'Z', "uart loopback");

    /* 3. SPI loopback, mode 0 and mode 3, MSB and LSB first */
    SPI_CLKDIV = 1;
    int spi_ok = 1;
    const uint8_t pat[4] = {0xA5, 0x3C, 0x00, 0xFF};
    for (uint32_t mode = 0; mode < 4; mode += 3) {
        /* change the mode only with CS high: a CPOL change moves SCLK */
        SPI_CTRL = 1u | (mode << 1) | ((mode == 3) ? (1u << 3) : 0u);
        SPI_CS = 0;
        for (int i = 0; i < 4; i++)
            spi_ok &= (spi_xfer(pat[i]) == pat[i]);
        SPI_CS = 1;
    }
    SPI_CTRL = 0;
    check(spi_ok, "spi loopback modes 0/3");

    /* 4. GPIO loopback and edge interrupt via IRQ controller (MEI) */
    GPIO_OUT = 0;
    GPIO_OE = 0xFF;
    GPIO_OUT = 0x5A;
    for (volatile int d = 0; d < 4; d++)
        ;
    check(GPIO_IN == 0x5A, "gpio out->in");
    GPIO_OUT = 0;
    GPIO_IS = 0xFF;
    GPIO_IE = 0x01;
    IRQC_ENABLE = 1u << 3;                  /* GPIO source */
    csr_set(mie, MIE_MEIE);
    csr_set(mstatus, MSTATUS_MIE);
    GPIO_OUT = 0x01;                        /* rising edge on pin 0 */
    for (volatile int d = 0; d < 20 && n_mei == 0; d++)
        ;
    check(n_mei == 1 && last_irq_id == 4 && GPIO_IS == 0, "gpio edge irq (MEI, IRQ_ID=4)");
    csr_clear(mie, MIE_MEIE);

    /* 5. Timer compare interrupt (MTI) */
    TIMER_TCR = 0;
    TIMER_TDR1 = 0;
    TIMER_TDR0 = 0;
    TIMER_TCMP1 = 0;
    TIMER_TCMP0 = 500;
    TIMER_TIER = 1;
    csr_set(mie, MIE_MTIE);
    TIMER_TCR = 1;                          /* timer_en, every clock */
    while (n_mti == 0 && TIMER_TDR0 < 5000)
        ;
    check(n_mti == 1 && TIMER_TDR0 >= 500, "timer irq (MTI)");
    csr_clear(mie, MIE_MTIE);
    TIMER_TCR = 0;

    /* 6. I2C EEPROM: page write of 4 bytes, then random read */
    I2C_CTRL = 1;
    const uint8_t data[4] = {0xDE, 0xAD, 0xBE, 0xEF};
    uint32_t nack = i2c_write(0xA0, I2C_CMD_START);
    nack |= i2c_write(0x01, 0);
    nack |= i2c_write(0x20, 0);
    for (int i = 0; i < 4; i++)
        nack |= i2c_write(data[i], (i == 3) ? I2C_CMD_STOP : 0);
    eeprom_wait_ready();
    nack |= i2c_write(0xA0, I2C_CMD_START);
    nack |= i2c_write(0x01, 0);
    nack |= i2c_write(0x20, 0);
    nack |= i2c_write(0xA1, I2C_CMD_START);
    int ee_ok = (nack == 0);
    for (int i = 0; i < 4; i++)
        ee_ok &= (i2c_read((i == 3) ? (I2C_CMD_NACK | I2C_CMD_STOP) : 0) == data[i]);
    check(ee_ok, "i2c eeprom write/read");

    /* 7. I2C NACK from a missing device */
    I2C_ISR = 0x3;
    nack = i2c_write(0xA2 | 0x10, I2C_CMD_START | I2C_CMD_STOP);
    check(nack != 0 && (I2C_ISR & 0x2), "i2c nack on wrong address");
    I2C_ISR = 0x3;

    /* 8. Bus error: disabled APB slot -> load access fault */
    uint32_t before = n_exc;
    (void)REG32(0x10007000u);
    check(n_exc == before + 1 && last_cause == 5, "bus error trap (SLVERR)");

    if (fails == 0) {
        uart_puts("@@PASS\n");
    } else {
        uart_puts("@@FAIL ");
        uart_putdec(fails);
        uart_puts("\n");
    }
    uart_flush();
    return 0;
}
