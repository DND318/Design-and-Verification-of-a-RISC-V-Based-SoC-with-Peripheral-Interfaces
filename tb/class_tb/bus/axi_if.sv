// AXI4-Lite interface
interface axi_if (input logic clk);
  logic        rst_n;
  logic [31:0] awaddr;  logic [2:0] awprot; logic awvalid, awready;
  logic [31:0] wdata;   logic [3:0] wstrb;  logic wvalid,  wready;
  logic [1:0]  bresp;   logic       bvalid, bready;
  logic [31:0] araddr;  logic [2:0] arprot; logic arvalid, arready;
  logic [31:0] rdata;   logic [1:0] rresp;  logic rvalid,  rready;
  logic        direct;      // port 0 only: the direct AXI port drives the xbar input

  modport mst (input clk, rst_n, awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid,
               output awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready, araddr, arprot, arvalid, rready);
  modport slv (input clk, rst_n, awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready, araddr, arprot, arvalid, rready,
               output awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid);
endinterface
