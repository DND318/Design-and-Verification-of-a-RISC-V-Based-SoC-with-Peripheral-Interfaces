// CPU memory port interface
interface cpu_if (input logic clk);
  logic        rst_n;
  logic        req, instr, we;
  logic [3:0]  wstrb;
  logic [31:0] addr, wdata;
  logic [31:0] rdata;
  logic        ready, err;
  logic        direct;

  modport drv (input clk, rst_n, rdata, ready, err, output req, instr, we, wstrb, addr, wdata, direct);
  modport mon (input clk, rst_n, req, instr, we, wstrb, addr, wdata, rdata, ready, err);
endinterface
