// APB4 interface of the class-based testbenches (course style: interface +
// virtual interface handles in the driver and the monitor).
// The DUT is the APB slave, the testbench is the master.
// cyc counts rising clock edges since time 0; the driver uses it to time-stamp
// transfers for the tests that measure a number of clock cycles.
interface apb_if (input logic clk);
  logic        rst_n;
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [11:0] paddr;
  logic [31:0] pwdata;
  logic [3:0]  pstrb;
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr;
  logic [7:0]  irq;      // interrupt outputs of the DUT (bit 0 for a block with one irq)

  longint unsigned cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  // Master side (driver) and passive side (monitor)
  modport drv (input clk, rst_n, prdata, pready, pslverr, irq, cyc,
               output psel, penable, pwrite, paddr, pwdata, pstrb);
  modport mon (input clk, rst_n, psel, penable, pwrite, paddr, pwdata, pstrb,
               prdata, pready, pslverr, irq, cyc);
endinterface
