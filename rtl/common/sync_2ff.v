`timescale 1ns/1ps
// Two-flip-flop synchronizer for asynchronous input pins (one bit per lane).
// RESET_VAL is the value of both stages during reset, so an idle-High line
// (UART RX, I2C SCL/SDA) does not show a false edge when reset is released.
module sync_2ff #(
  parameter WIDTH     = 1,
  parameter RESET_VAL = 0
) (
  input  wire             clk_i,
  input  wire             rst_ni,
  input  wire [WIDTH-1:0] d_i,
  output wire [WIDTH-1:0] q_o
);

  localparam [WIDTH-1:0] RST = RESET_VAL;

  reg [WIDTH-1:0] meta_q, sync_q;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      meta_q <= RST;
      sync_q <= RST;
    end else begin
      meta_q <= d_i;
      sync_q <= meta_q;
    end
  end

  assign q_o = sync_q;

endmodule
