// IRQC interface
interface irqc_if (input logic clk);
  logic       rst_n;
  logic [3:0] irq_in;
  logic       irq;

  modport drv (input clk, output irq_in);
  modport mon (input clk, rst_n, irq_in, irq);
endinterface
