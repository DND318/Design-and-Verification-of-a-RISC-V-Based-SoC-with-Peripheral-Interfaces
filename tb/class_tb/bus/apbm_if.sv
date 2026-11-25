// APB interface of the bridge (16 slots)
interface apbm_if (input logic clk);
  logic         rst_n;
  logic [15:0]  psel;
  logic         penable, pwrite;
  logic [11:0]  paddr;
  logic [31:0]  pwdata;
  logic [3:0]   pstrb;
  logic [2:0]   pprot;
  logic [511:0] prdata;      // slot n at [32*n +: 32]
  logic [15:0]  pready, pslverr;

  modport slv (input clk, rst_n, psel, penable, pwrite, paddr, pwdata, pstrb, pprot, output prdata, pready, pslverr);
  modport mon (input clk, rst_n, psel, penable, pwrite, paddr, pwdata, pstrb, pprot, prdata, pready, pslverr);
endinterface
