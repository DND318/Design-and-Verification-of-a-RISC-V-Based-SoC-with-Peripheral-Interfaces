// I2C interface
interface i2c_if (input logic clk);
  logic rst_n;
  logic scl, sda;
  logic scl_oe, sda_oe;
  logic scl_o, sda_o;
  logic sda_low;
  logic ext_scl_low, ext_sda_low;
  logic irq;

  modport drv (input clk, scl, sda, output sda_low, ext_scl_low, ext_sda_low);
  modport mon (input clk, rst_n, scl, sda, scl_oe, sda_oe, scl_o, sda_o, sda_low, irq);
endinterface
