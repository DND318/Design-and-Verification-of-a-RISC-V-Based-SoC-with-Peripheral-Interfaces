`timescale 1ns/1ps
module rv32_regfile (
  input  wire        clk_i,
  input  wire [4:0]  raddr1_i,
  input  wire [4:0]  raddr2_i,
  output wire [31:0] rdata1_o,
  output wire [31:0] rdata2_o,
  input  wire        we_i,
  input  wire [4:0]  waddr_i,
  input  wire [31:0] wdata_i
);

  reg [31:0] regs_q [0:31];

  assign rdata1_o = (raddr1_i == 5'd0) ? 32'd0 : regs_q[raddr1_i];
  assign rdata2_o = (raddr2_i == 5'd0) ? 32'd0 : regs_q[raddr2_i];

  always @(posedge clk_i) begin
    if (we_i && (waddr_i != 5'd0)) regs_q[waddr_i] <= wdata_i;
  end

endmodule
