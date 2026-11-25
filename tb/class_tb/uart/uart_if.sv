// UART interface
interface uart_if (input logic clk);
  logic rx;
  logic tx;
  logic tx_ser;

  modport drv (input clk, output rx);
  modport mon (input clk, rx, tx, tx_ser);
endinterface
