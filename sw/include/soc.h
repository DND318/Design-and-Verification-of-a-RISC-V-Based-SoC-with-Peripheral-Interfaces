/* Register addresses of the SoC (doc/spec, generated values copied by hand
   from doc/spec/regmap.py). Plain macros only: there is no driver library. */
#ifndef SOC_H
#define SOC_H

#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(addr))

#define CLK_HZ        50000000u

#define UART_BASE     0x10000000u
#define SPI_BASE      0x10001000u
#define I2C_BASE      0x10002000u
#define TIMER_BASE    0x10003000u
#define IRQC_BASE     0x10004000u
#define GPIO_BASE     0x10005000u

/* UART */
#define UART_CTRL     REG32(UART_BASE + 0x00)
#define UART_BAUD     REG32(UART_BASE + 0x04)
#define UART_STATUS   REG32(UART_BASE + 0x08)
#define UART_TXDATA   REG32(UART_BASE + 0x0C)
#define UART_RXDATA   REG32(UART_BASE + 0x10)
#define UART_IER      REG32(UART_BASE + 0x14)
#define UART_ISR      REG32(UART_BASE + 0x18)
#define UART_CTRL_TX_EN    (1u << 0)
#define UART_CTRL_RX_EN    (1u << 1)
#define UART_ST_TX_FULL    (1u << 0)
#define UART_ST_TX_EMPTY   (1u << 1)
#define UART_ST_RX_EMPTY   (1u << 3)
#define UART_ST_TX_BUSY    (1u << 4)

/* SPI */
#define SPI_CTRL      REG32(SPI_BASE + 0x00)
#define SPI_CLKDIV    REG32(SPI_BASE + 0x04)
#define SPI_CS        REG32(SPI_BASE + 0x08)
#define SPI_STATUS    REG32(SPI_BASE + 0x0C)
#define SPI_TXDATA    REG32(SPI_BASE + 0x10)
#define SPI_RXDATA    REG32(SPI_BASE + 0x14)
#define SPI_IER       REG32(SPI_BASE + 0x18)
#define SPI_ISR       REG32(SPI_BASE + 0x1C)
#define SPI_ST_BUSY        (1u << 0)
#define SPI_ST_TX_EMPTY    (1u << 2)
#define SPI_ST_RX_EMPTY    (1u << 4)

/* I2C */
#define I2C_CTRL      REG32(I2C_BASE + 0x00)
#define I2C_PRESCALE  REG32(I2C_BASE + 0x04)
#define I2C_CMD       REG32(I2C_BASE + 0x08)
#define I2C_TXDATA    REG32(I2C_BASE + 0x0C)
#define I2C_RXDATA    REG32(I2C_BASE + 0x10)
#define I2C_STATUS    REG32(I2C_BASE + 0x14)
#define I2C_IER       REG32(I2C_BASE + 0x18)
#define I2C_ISR       REG32(I2C_BASE + 0x1C)
#define I2C_CMD_START      (1u << 0)
#define I2C_CMD_STOP       (1u << 1)
#define I2C_CMD_WRITE      (1u << 2)
#define I2C_CMD_READ       (1u << 3)
#define I2C_CMD_NACK       (1u << 4)
#define I2C_ST_BUSY        (1u << 0)
#define I2C_ST_RX_NACK     (1u << 1)

/* Timer (RISC-V mtime / mtimecmp) */
#define TIMER_TCR     REG32(TIMER_BASE + 0x00)
#define TIMER_TIER    REG32(TIMER_BASE + 0x04)
#define TIMER_TISR    REG32(TIMER_BASE + 0x08)
#define TIMER_TDR0    REG32(TIMER_BASE + 0x10)
#define TIMER_TDR1    REG32(TIMER_BASE + 0x14)
#define TIMER_TCMP0   REG32(TIMER_BASE + 0x18)
#define TIMER_TCMP1   REG32(TIMER_BASE + 0x1C)

/* IRQ controller */
#define IRQC_PENDING  REG32(IRQC_BASE + 0x00)
#define IRQC_ENABLE   REG32(IRQC_BASE + 0x04)
#define IRQC_STATUS   REG32(IRQC_BASE + 0x08)
#define IRQC_ID       REG32(IRQC_BASE + 0x0C)

/* GPIO */
#define GPIO_OUT      REG32(GPIO_BASE + 0x00)
#define GPIO_OE       REG32(GPIO_BASE + 0x04)
#define GPIO_IN       REG32(GPIO_BASE + 0x08)
#define GPIO_IE       REG32(GPIO_BASE + 0x0C)
#define GPIO_IS       REG32(GPIO_BASE + 0x10)

/* mcause values */
#define MCAUSE_MTI    0x80000007u
#define MCAUSE_MEI    0x8000000Bu

/* CSR access */
#define csr_read(csr) ({ uint32_t v_; __asm__ volatile ("csrr %0, " #csr : "=r"(v_)); v_; })
#define csr_write(csr, v) __asm__ volatile ("csrw " #csr ", %0" :: "r"(v))
#define csr_set(csr, v)   __asm__ volatile ("csrs " #csr ", %0" :: "r"(v))
#define csr_clear(csr, v) __asm__ volatile ("csrc " #csr ", %0" :: "r"(v))
#define MSTATUS_MIE   (1u << 3)
#define MIE_MTIE      (1u << 7)
#define MIE_MEIE      (1u << 11)

/* Minimal console helpers (inline, no library) */
static inline void uart_init(uint32_t baud_div)
{
    UART_BAUD = baud_div;
    UART_CTRL = UART_CTRL_TX_EN | UART_CTRL_RX_EN;
}

static inline void uart_putc(char c)
{
    while (UART_STATUS & UART_ST_TX_FULL)
        ;
    UART_TXDATA = (uint8_t)c;
}

static inline void uart_puts(const char *s)
{
    while (*s) {
        if (*s == '\n')
            uart_putc('\r');
        uart_putc(*s++);
    }
}

static inline void uart_puthex(uint32_t v)
{
    for (int i = 28; i >= 0; i -= 4)
        uart_putc("0123456789ABCDEF"[(v >> i) & 0xF]);
}

static inline void uart_putdec(uint32_t v)
{
    char buf[11];
    int n = 0;
    do {
        buf[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    while (n)
        uart_putc(buf[--n]);
}

/* Wait until every byte has left the transmitter */
static inline void uart_flush(void)
{
    while ((UART_STATUS & (UART_ST_TX_EMPTY | UART_ST_TX_BUSY)) != UART_ST_TX_EMPTY)
        ;
}

#endif
