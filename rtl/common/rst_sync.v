`timescale 1ns/1ps
// Reset synchronizer: rst_no is asserted asynchronously with rst_ni and
// released synchronously, two clock edges after rst_ni goes High.
module rst_sync (
  input  wire clk_i,
  input  wire rst_ni,
  output wire rst_no
);

  reg [1:0] sync_q;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) sync_q <= 2'b00;
    else         sync_q <= {sync_q[0], 1'b1};
  end

  assign rst_no = sync_q[1];

endmodule
