`timescale 1ns/1ps
module rv32_branch_unit (
  input  wire [2:0]  funct3_i,
  input  wire [31:0] a_i,
  input  wire [31:0] b_i,
  output reg         taken_o
);

  always @* begin
    case (funct3_i)
      3'b000:  taken_o = (a_i == b_i);
      3'b001:  taken_o = (a_i != b_i);
      3'b100:  taken_o = ($signed(a_i) <  $signed(b_i));
      3'b101:  taken_o = ($signed(a_i) >= $signed(b_i));
      3'b110:  taken_o = (a_i <  b_i);
      3'b111:  taken_o = (a_i >= b_i);
      default: taken_o = 1'b0;
    endcase
  end

endmodule
