// RV32IM + Zicsr constants shared by the core sub-modules (Verilog-2005).
// Replaces the `define list of the prethesis rv32im_multicycle.v.
// This file is listed first in every filelist; the macros are global to the
// compilation, so the RTL files do not `include it.
`ifndef RV32_DEFINES_VH
`define RV32_DEFINES_VH

// Base opcodes (instr[6:0])
`define RV32_OPC_LUI       7'b0110111
`define RV32_OPC_AUIPC     7'b0010111
`define RV32_OPC_JAL       7'b1101111
`define RV32_OPC_JALR      7'b1100111
`define RV32_OPC_BRANCH    7'b1100011
`define RV32_OPC_LOAD      7'b0000011
`define RV32_OPC_STORE     7'b0100011
`define RV32_OPC_OP_IMM    7'b0010011
`define RV32_OPC_OP        7'b0110011
`define RV32_OPC_MISC_MEM  7'b0001111
`define RV32_OPC_SYSTEM    7'b1110011

// Full encodings of the SYSTEM instructions without operands
`define RV32_INSTR_ECALL   32'h0000_0073
`define RV32_INSTR_EBREAK  32'h0010_0073
`define RV32_INSTR_MRET    32'h3020_0073
`define RV32_INSTR_WFI     32'h1050_0073
`define RV32_INSTR_NOP     32'h0000_0013

// ALU operations (4 bit)
`define RV32_ALU_ADD   4'd0
`define RV32_ALU_SUB   4'd1
`define RV32_ALU_SLL   4'd2
`define RV32_ALU_SLT   4'd3
`define RV32_ALU_SLTU  4'd4
`define RV32_ALU_XOR   4'd5
`define RV32_ALU_SRL   4'd6
`define RV32_ALU_SRA   4'd7
`define RV32_ALU_OR    4'd8
`define RV32_ALU_AND   4'd9

// Immediate formats (3 bit)
`define RV32_IMM_I  3'd0
`define RV32_IMM_S  3'd1
`define RV32_IMM_B  3'd2
`define RV32_IMM_U  3'd3
`define RV32_IMM_J  3'd4

// CSR addresses implemented by rv32_csr
`define RV32_CSR_MSTATUS    12'h300
`define RV32_CSR_MISA       12'h301
`define RV32_CSR_MIE        12'h304
`define RV32_CSR_MTVEC      12'h305
`define RV32_CSR_MSCRATCH   12'h340
`define RV32_CSR_MEPC       12'h341
`define RV32_CSR_MCAUSE     12'h342
`define RV32_CSR_MTVAL      12'h343
`define RV32_CSR_MIP        12'h344
`define RV32_CSR_MCYCLE     12'hB00
`define RV32_CSR_MINSTRET   12'hB02
`define RV32_CSR_MCYCLEH    12'hB80
`define RV32_CSR_MINSTRETH  12'hB82
// Zicntr user counters: read-only shadows of mcycle / minstret
`define RV32_CSR_CYCLE      12'hC00
`define RV32_CSR_INSTRET    12'hC02
`define RV32_CSR_CYCLEH     12'hC80
`define RV32_CSR_INSTRETH   12'hC82
`define RV32_CSR_MVENDORID  12'hF11
`define RV32_CSR_MARCHID    12'hF12
`define RV32_CSR_MIMPID     12'hF13
`define RV32_CSR_MHARTID    12'hF14

// misa: MXL = 1 (32 bit), extensions I and M
`define RV32_MISA_VALUE  32'h4000_1100

// mcause exception codes (Interrupt = 0)
`define RV32_EXC_INSTR_MISALIGNED  4'd0
`define RV32_EXC_INSTR_ACCESS      4'd1
`define RV32_EXC_ILLEGAL_INSTR     4'd2
`define RV32_EXC_BREAKPOINT        4'd3
`define RV32_EXC_LOAD_MISALIGNED   4'd4
`define RV32_EXC_LOAD_ACCESS       4'd5
`define RV32_EXC_STORE_MISALIGNED  4'd6
`define RV32_EXC_STORE_ACCESS      4'd7
`define RV32_EXC_ECALL_M           4'd11

// mcause interrupt codes (Interrupt = 1)
`define RV32_IRQ_M_TIMER     4'd7
`define RV32_IRQ_M_EXTERNAL  4'd11

`endif
