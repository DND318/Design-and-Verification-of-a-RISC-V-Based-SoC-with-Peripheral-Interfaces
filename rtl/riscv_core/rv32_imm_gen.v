`timescale 1ns/1ps
module rv32_imm_gen (
  input  wire [31:7] instr_i,
  input  wire [2:0]  imm_type_i,
  output reg  [31:0] imm_o
);

  always @* begin
    case (imm_type_i)
      `RV32_IMM_I: imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
      `RV32_IMM_S: imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
      `RV32_IMM_B: imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
      `RV32_IMM_U: imm_o = {instr_i[31:12], 12'h000};
      `RV32_IMM_J: imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
      default:     imm_o = 32'd0;
    endcase
  end

endmodule
