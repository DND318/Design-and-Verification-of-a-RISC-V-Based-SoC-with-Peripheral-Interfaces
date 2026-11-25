`timescale 1ns/1ps
module rv32_alu (
  input  wire [31:0] a_i,
  input  wire [31:0] b_i,
  input  wire [3:0]  op_i,
  output reg  [31:0] result_o
);

  wire [4:0] shamt = b_i[4:0];

  always @* begin
    case (op_i)
      `RV32_ALU_ADD:  result_o = a_i + b_i;
      `RV32_ALU_SUB:  result_o = a_i - b_i;
      `RV32_ALU_SLL:  result_o = a_i << shamt;
      `RV32_ALU_SLT:  result_o = {31'b0, $signed(a_i) < $signed(b_i)};
      `RV32_ALU_SLTU: result_o = {31'b0, a_i < b_i};
      `RV32_ALU_XOR:  result_o = a_i ^ b_i;
      `RV32_ALU_SRL:  result_o = a_i >> shamt;
      `RV32_ALU_SRA:  result_o = $signed(a_i) >>> shamt;
      `RV32_ALU_OR:   result_o = a_i | b_i;
      `RV32_ALU_AND:  result_o = a_i & b_i;
      default:        result_o = a_i + b_i;
    endcase
  end

endmodule
