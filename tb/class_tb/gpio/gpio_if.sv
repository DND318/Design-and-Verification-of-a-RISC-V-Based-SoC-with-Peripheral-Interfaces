// GPIO interface
interface gpio_if (input logic clk);
  logic       rst_n;
  logic [7:0] gpio_i;
  logic [7:0] gpio_o;
  logic [7:0] gpio_oe;
  logic       irq;

  modport drv (input clk, output gpio_i);
  modport mon (input clk, rst_n, gpio_i, gpio_o, gpio_oe, irq);
endinterface
