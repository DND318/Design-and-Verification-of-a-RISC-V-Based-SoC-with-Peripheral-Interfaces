// SPI interface
interface spi_if (input logic clk);
  logic rst_n;
  logic sclk;
  logic mosi;
  logic miso;
  logic cs_n;
  logic irq;

  modport drv (input clk, rst_n, sclk, cs_n, output miso);
  modport mon (input clk, rst_n, sclk, mosi, miso, cs_n, irq);
endinterface
