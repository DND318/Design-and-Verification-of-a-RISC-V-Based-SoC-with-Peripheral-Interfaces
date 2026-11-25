`timescale 1ns/1ps
module rv32_decoder (
  input  wire [31:0] instr_i,
  output reg         illegal_o,
  output reg         rd_we_o,
  output reg  [2:0]  imm_type_o,
  output reg  [3:0]  alu_op_o,
  output reg         alu_src_imm_o,
  output reg         is_lui_o,
  output reg         is_auipc_o,
  output reg         is_jal_o,
  output reg         is_jalr_o,
  output reg         is_branch_o,
  output reg         is_load_o,
  output reg         is_store_o,
  output reg         is_muldiv_o,
  output reg         is_csr_o,
  output reg         is_ecall_o,
  output reg         is_ebreak_o,
  output reg         is_mret_o,
  output reg         is_nop_o
);

  wire [6:0] opcode = instr_i[6:0];
  wire [2:0] funct3 = instr_i[14:12];
  wire [6:0] funct7 = instr_i[31:25];

  always @* begin
    illegal_o     = 1'b0;
    rd_we_o       = 1'b0;
    imm_type_o    = `RV32_IMM_I;
    alu_op_o      = `RV32_ALU_ADD;
    alu_src_imm_o = 1'b0;
    is_lui_o      = 1'b0;
    is_auipc_o    = 1'b0;
    is_jal_o      = 1'b0;
    is_jalr_o     = 1'b0;
    is_branch_o   = 1'b0;
    is_load_o     = 1'b0;
    is_store_o    = 1'b0;
    is_muldiv_o   = 1'b0;
    is_csr_o      = 1'b0;
    is_ecall_o    = 1'b0;
    is_ebreak_o   = 1'b0;
    is_mret_o     = 1'b0;
    is_nop_o      = 1'b0;

    case (opcode)
      `RV32_OPC_LUI: begin
        is_lui_o   = 1'b1;
        rd_we_o    = 1'b1;
        imm_type_o = `RV32_IMM_U;
      end

      `RV32_OPC_AUIPC: begin
        is_auipc_o = 1'b1;
        rd_we_o    = 1'b1;
        imm_type_o = `RV32_IMM_U;
      end

      `RV32_OPC_JAL: begin
        is_jal_o   = 1'b1;
        rd_we_o    = 1'b1;
        imm_type_o = `RV32_IMM_J;
      end

      `RV32_OPC_JALR: begin
        is_jalr_o  = 1'b1;
        rd_we_o    = 1'b1;
        imm_type_o = `RV32_IMM_I;
        illegal_o  = (funct3 != 3'b000);
      end

      `RV32_OPC_BRANCH: begin
        is_branch_o = 1'b1;
        imm_type_o  = `RV32_IMM_B;
        illegal_o   = (funct3 == 3'b010) || (funct3 == 3'b011);
      end

      `RV32_OPC_LOAD: begin
        is_load_o  = 1'b1;
        rd_we_o    = 1'b1;
        imm_type_o = `RV32_IMM_I;
        illegal_o  = (funct3 == 3'b011) || (funct3 == 3'b110) || (funct3 == 3'b111);
      end

      `RV32_OPC_STORE: begin
        is_store_o = 1'b1;
        imm_type_o = `RV32_IMM_S;
        illegal_o  = funct3[2] || (funct3 == 3'b011);
      end

      `RV32_OPC_OP_IMM: begin
        rd_we_o       = 1'b1;
        imm_type_o    = `RV32_IMM_I;
        alu_src_imm_o = 1'b1;
        case (funct3)
          3'b000: alu_op_o = `RV32_ALU_ADD;
          3'b010: alu_op_o = `RV32_ALU_SLT;
          3'b011: alu_op_o = `RV32_ALU_SLTU;
          3'b100: alu_op_o = `RV32_ALU_XOR;
          3'b110: alu_op_o = `RV32_ALU_OR;
          3'b111: alu_op_o = `RV32_ALU_AND;
          3'b001: begin
            alu_op_o  = `RV32_ALU_SLL;
            illegal_o = (funct7 != 7'b0000000);
          end
          default: begin  // 3'b101
            alu_op_o  = funct7[5] ? `RV32_ALU_SRA : `RV32_ALU_SRL;
            illegal_o = (funct7 != 7'b0000000) && (funct7 != 7'b0100000);
          end
        endcase
      end

      `RV32_OPC_OP: begin
        rd_we_o = 1'b1;
        case (funct7)
          7'b0000000: begin
            case (funct3)
              3'b000:  alu_op_o = `RV32_ALU_ADD;
              3'b001:  alu_op_o = `RV32_ALU_SLL;
              3'b010:  alu_op_o = `RV32_ALU_SLT;
              3'b011:  alu_op_o = `RV32_ALU_SLTU;
              3'b100:  alu_op_o = `RV32_ALU_XOR;
              3'b101:  alu_op_o = `RV32_ALU_SRL;
              3'b110:  alu_op_o = `RV32_ALU_OR;
              default: alu_op_o = `RV32_ALU_AND;
            endcase
          end
          7'b0100000: begin
            case (funct3)
              3'b000:  alu_op_o  = `RV32_ALU_SUB;
              3'b101:  alu_op_o  = `RV32_ALU_SRA;
              default: illegal_o = 1'b1;
            endcase
          end
          7'b0000001: is_muldiv_o = 1'b1;
          default:    illegal_o   = 1'b1;
        endcase
      end

      `RV32_OPC_MISC_MEM: begin
        // FENCE and FENCE.I: no caches or buffers, so they act as NOP
        is_nop_o  = 1'b1;
        illegal_o = (funct3 != 3'b000) && (funct3 != 3'b001);
      end

      `RV32_OPC_SYSTEM: begin
        if (funct3 == 3'b000) begin
          case (instr_i)
            `RV32_INSTR_ECALL:  is_ecall_o  = 1'b1;
            `RV32_INSTR_EBREAK: is_ebreak_o = 1'b1;
            `RV32_INSTR_MRET:   is_mret_o   = 1'b1;
            `RV32_INSTR_WFI:    is_nop_o    = 1'b1;
            default:            illegal_o   = 1'b1;
          endcase
        end else if (funct3 == 3'b100) begin
          illegal_o = 1'b1;
        end else begin
          is_csr_o = 1'b1;
          rd_we_o  = 1'b1;
        end
      end

      default: illegal_o = 1'b1;
    endcase

    if (illegal_o) rd_we_o = 1'b0;
  end

endmodule
