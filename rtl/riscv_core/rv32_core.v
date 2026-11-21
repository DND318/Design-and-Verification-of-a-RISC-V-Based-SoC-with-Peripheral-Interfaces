`timescale 1ns/1ps
module rv32_core #(
  parameter [31:0] BOOT_ADDR = 32'h0000_0000
) (
  input  wire        clk_i,
  input  wire        rst_ni,

  output wire        mem_req_o,
  output wire        mem_instr_o,
  output wire        mem_we_o,
  output wire [3:0]  mem_wstrb_o,
  output wire [31:0] mem_addr_o,
  output wire [31:0] mem_wdata_o,
  input  wire [31:0] mem_rdata_i,
  input  wire        mem_ready_i,
  input  wire        mem_err_i,

  input  wire        irq_mtip_i,
  input  wire        irq_meip_i
);

  localparam [2:0] S_IF   = 3'd0,
                   S_ID   = 3'd1,
                   S_EX   = 3'd2,
                   S_MEM  = 3'd3,
                   S_DIV  = 3'd4,
                   S_WB   = 3'd5,
                   S_TRAP = 3'd6;

  reg  [2:0]  state_q, state_d;
  reg  [31:0] pc_q, pc_d;
  reg  [31:0] ir_q;
  reg  [31:0] a_q, b_q;           // register operands, latched in ID
  reg  [31:0] alu_out_q;          // EX result or address
  reg  [31:0] mdr_q;              // load data
  reg         fetch_busy_q;       // fetch request issued, waiting for ready

  reg         trap_set;           // capture a trap this cycle
  reg         trap_irq_d,  trap_irq_q;
  reg  [3:0]  trap_code_d, trap_code_q;
  reg  [31:0] trap_tval_d, trap_tval_q;

  // ---------------- decode ----------------
  wire        illegal, rd_we, alu_src_imm;
  wire [2:0]  imm_type;
  wire [3:0]  alu_op;
  wire        is_lui, is_auipc, is_jal, is_jalr, is_branch, is_load, is_store;
  wire        is_muldiv, is_csr, is_ecall, is_ebreak, is_mret, is_nop;

  wire [2:0]  funct3 = ir_q[14:12];
  wire [4:0]  rs1    = ir_q[19:15];
  wire [4:0]  rs2    = ir_q[24:20];
  wire [4:0]  rd     = ir_q[11:7];

  rv32_decoder u_decoder (
    .instr_i       (ir_q),
    .illegal_o     (illegal),
    .rd_we_o       (rd_we),
    .imm_type_o    (imm_type),
    .alu_op_o      (alu_op),
    .alu_src_imm_o (alu_src_imm),
    .is_lui_o      (is_lui),
    .is_auipc_o    (is_auipc),
    .is_jal_o      (is_jal),
    .is_jalr_o     (is_jalr),
    .is_branch_o   (is_branch),
    .is_load_o     (is_load),
    .is_store_o    (is_store),
    .is_muldiv_o   (is_muldiv),
    .is_csr_o      (is_csr),
    .is_ecall_o    (is_ecall),
    .is_ebreak_o   (is_ebreak),
    .is_mret_o     (is_mret),
    .is_nop_o      (is_nop)
  );

  wire [31:0] imm;

  rv32_imm_gen u_imm_gen (
    .instr_i    (ir_q[31:7]),
    .imm_type_i (imm_type),
    .imm_o      (imm)
  );

  // ---------------- register file ----------------
  wire [31:0] rf_rdata1, rf_rdata2;
  reg  [31:0] rf_wdata;
  wire        rf_we = (state_q == S_WB) && rd_we;

  rv32_regfile u_regfile (
    .clk_i    (clk_i),
    .raddr1_i (rs1),
    .raddr2_i (rs2),
    .rdata1_o (rf_rdata1),
    .rdata2_o (rf_rdata2),
    .we_i     (rf_we),
    .waddr_i  (rd),
    .wdata_i  (rf_wdata)
  );

  // ---------------- execute ----------------
  wire [31:0] alu_result;
  wire        br_taken;
  wire [31:0] pc_plus4    = pc_q + 32'd4;
  wire [31:0] pc_imm      = pc_q + imm;
  wire [31:0] agen        = a_q + imm;
  wire [31:0] jalr_target = {agen[31:1], 1'b0};
  reg  [31:0] ex_result;

  rv32_alu u_alu (
    .a_i      (a_q),
    .b_i      (alu_src_imm ? imm : b_q),
    .op_i     (alu_op),
    .result_o (alu_result)
  );

  rv32_branch_unit u_branch (
    .funct3_i (funct3),
    .a_i      (a_q),
    .b_i      (b_q),
    .taken_o  (br_taken)
  );

  always @* begin
    if (is_lui)                    ex_result = imm;
    else if (is_auipc || is_jal)   ex_result = pc_imm;
    else if (is_jalr)              ex_result = jalr_target;
    else if (is_load || is_store)  ex_result = agen;
    else                           ex_result = alu_result;
  end

  // ---------------- multiply / divide ----------------
  wire        md_start = (state_q == S_EX) && is_muldiv;
  wire        md_done;
  wire [31:0] md_result;

  rv32_muldiv u_muldiv (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .start_i  (md_start),
    .funct3_i (funct3),
    .a_i      (a_q),
    .b_i      (b_q),
    .done_o   (md_done),
    .result_o (md_result)
  );

  // ---------------- load / store ----------------
  wire [31:0] lsu_wdata, lsu_load_data;
  wire [3:0]  lsu_wstrb;
  wire        lsu_misaligned;
  wire [1:0]  lsu_addr = (state_q == S_EX) ? agen[1:0] : alu_out_q[1:0];

  rv32_lsu u_lsu (
    .funct3_i     (funct3),
    .addr_lsb_i   (lsu_addr),
    .store_data_i (b_q),
    .mem_rdata_i  (mem_rdata_i),
    .mem_wdata_o  (lsu_wdata),
    .mem_wstrb_o  (lsu_wstrb),
    .load_data_o  (lsu_load_data),
    .misaligned_o (lsu_misaligned)
  );

  // ---------------- CSR ----------------
  wire        csr_we      = (funct3[1:0] == 2'b01) || (rs1 != 5'd0);
  wire [31:0] csr_operand = funct3[2] ? {27'b0, rs1} : a_q;
  wire        csr_wr_en   = (state_q == S_WB) && is_csr;
  wire [31:0] csr_rdata, mtvec, mepc;
  wire        csr_illegal;
  wire        irq_pending;
  wire [3:0]  irq_code;
  wire        trap_enter = (state_q == S_TRAP);
  reg         mret, instret;

  rv32_csr u_csr (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .csr_addr_i    (ir_q[31:20]),
    .csr_we_i      (csr_we),
    .csr_wr_en_i   (csr_wr_en),
    .csr_op_i      (funct3[1:0]),
    .csr_operand_i (csr_operand),
    .csr_rdata_o   (csr_rdata),
    .csr_illegal_o (csr_illegal),
    .trap_i        (trap_enter),
    .trap_irq_i    (trap_irq_q),
    .trap_code_i   (trap_code_q),
    .trap_epc_i    (pc_q[31:2]),
    .trap_tval_i   (trap_tval_q),
    .mret_i        (mret),
    .mtvec_o       (mtvec),
    .mepc_o        (mepc),
    .instret_i     (instret),
    .irq_mtip_i    (irq_mtip_i),
    .irq_meip_i    (irq_meip_i),
    .irq_pending_o (irq_pending),
    .irq_code_o    (irq_code)
  );

  // ---------------- control FSM ----------------
  // Interrupts are sampled before a fetch is issued, never during one
  wire irq_take = (state_q == S_IF) && !fetch_busy_q && irq_pending;

  always @* begin
    state_d     = state_q;
    pc_d        = pc_q;
    trap_set    = 1'b0;
    trap_irq_d  = 1'b0;
    trap_code_d = `RV32_EXC_ILLEGAL_INSTR;
    trap_tval_d = 32'd0;
    mret        = 1'b0;
    instret     = 1'b0;

    case (state_q)
      S_IF: begin
        if (irq_take) begin
          trap_set    = 1'b1;
          trap_irq_d  = 1'b1;
          trap_code_d = irq_code;
          state_d     = S_TRAP;
        end else if (mem_ready_i) begin
          if (mem_err_i) begin
            trap_set    = 1'b1;
            trap_code_d = `RV32_EXC_INSTR_ACCESS;
            trap_tval_d = pc_q;
            state_d     = S_TRAP;
          end else begin
            state_d = S_ID;
          end
        end
      end

      S_ID: begin
        if (illegal || (is_csr && csr_illegal)) begin
          trap_set    = 1'b1;
          trap_code_d = `RV32_EXC_ILLEGAL_INSTR;
          trap_tval_d = ir_q;
          state_d     = S_TRAP;
        end else if (is_ecall) begin
          trap_set    = 1'b1;
          trap_code_d = `RV32_EXC_ECALL_M;
          state_d     = S_TRAP;
        end else if (is_ebreak) begin
          trap_set    = 1'b1;
          trap_code_d = `RV32_EXC_BREAKPOINT;
          state_d     = S_TRAP;
        end else if (is_mret) begin
          mret    = 1'b1;
          instret = 1'b1;
          pc_d    = mepc;
          state_d = S_IF;
        end else if (is_nop) begin
          instret = 1'b1;
          pc_d    = pc_plus4;
          state_d = S_IF;
        end else begin
          state_d = S_EX;
        end
      end

      S_EX: begin
        if (is_branch) begin
          if (br_taken && (pc_imm[1:0] != 2'b00)) begin
            trap_set    = 1'b1;
            trap_code_d = `RV32_EXC_INSTR_MISALIGNED;
            trap_tval_d = pc_imm;
            state_d     = S_TRAP;
          end else begin
            instret = 1'b1;
            pc_d    = br_taken ? pc_imm : pc_plus4;
            state_d = S_IF;
          end
        end else if ((is_jal || is_jalr) && (ex_result[1:0] != 2'b00)) begin
          trap_set    = 1'b1;
          trap_code_d = `RV32_EXC_INSTR_MISALIGNED;
          trap_tval_d = ex_result;
          state_d     = S_TRAP;
        end else if (is_load || is_store) begin
          if (lsu_misaligned) begin
            trap_set    = 1'b1;
            trap_code_d = is_store ? `RV32_EXC_STORE_MISALIGNED : `RV32_EXC_LOAD_MISALIGNED;
            trap_tval_d = agen;
            state_d     = S_TRAP;
          end else begin
            state_d = S_MEM;
          end
        end else if (is_muldiv) begin
          state_d = S_DIV;
        end else begin
          state_d = S_WB;
        end
      end

      S_MEM: begin
        if (mem_ready_i) begin
          if (mem_err_i) begin
            trap_set    = 1'b1;
            trap_code_d = is_store ? `RV32_EXC_STORE_ACCESS : `RV32_EXC_LOAD_ACCESS;
            trap_tval_d = alu_out_q;
            state_d     = S_TRAP;
          end else if (is_store) begin
            instret = 1'b1;
            pc_d    = pc_plus4;
            state_d = S_IF;
          end else begin
            state_d = S_WB;
          end
        end
      end

      S_DIV: begin
        if (md_done) state_d = S_WB;
      end

      S_WB: begin
        instret = 1'b1;
        pc_d    = (is_jal || is_jalr) ? alu_out_q : pc_plus4;
        state_d = S_IF;
      end

      S_TRAP: begin
        pc_d    = mtvec;
        state_d = S_IF;
      end

      default: state_d = S_IF;
    endcase
  end

  // ---------------- write back ----------------
  always @* begin
    if (is_load)                 rf_wdata = mdr_q;
    else if (is_jal || is_jalr)  rf_wdata = pc_plus4;
    else if (is_csr)             rf_wdata = csr_rdata;
    else                         rf_wdata = alu_out_q;
  end

  // ---------------- registers ----------------
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= S_IF;
      pc_q         <= BOOT_ADDR;
      ir_q         <= `RV32_INSTR_NOP;
      a_q          <= 32'd0;
      b_q          <= 32'd0;
      alu_out_q    <= 32'd0;
      mdr_q        <= 32'd0;
      fetch_busy_q <= 1'b0;
      trap_irq_q   <= 1'b0;
      trap_code_q  <= 4'd0;
      trap_tval_q  <= 32'd0;
    end else begin
      state_q      <= state_d;
      pc_q         <= pc_d;
      fetch_busy_q <= mem_req_o && mem_instr_o && !mem_ready_i;

      if (state_q == S_IF && mem_ready_i && !mem_err_i) ir_q <= mem_rdata_i;

      if (state_q == S_ID) begin
        a_q <= rf_rdata1;
        b_q <= rf_rdata2;
      end

      if (state_q == S_EX)                   alu_out_q <= ex_result;
      else if (state_q == S_DIV && md_done)  alu_out_q <= md_result;

      if (state_q == S_MEM && mem_ready_i) mdr_q <= lsu_load_data;

      if (trap_set) begin
        trap_irq_q  <= trap_irq_d;
        trap_code_q <= trap_code_d;
        trap_tval_q <= trap_tval_d;
      end
    end
  end

  // ---------------- memory port ----------------
  assign mem_instr_o = (state_q == S_IF);
  assign mem_req_o   = ((state_q == S_IF) && !irq_take) || (state_q == S_MEM);
  assign mem_we_o    = (state_q == S_MEM) && is_store;
  assign mem_addr_o  = (state_q == S_IF) ? pc_q : alu_out_q;
  assign mem_wdata_o = lsu_wdata;
  assign mem_wstrb_o = mem_we_o ? lsu_wstrb : 4'b0000;

endmodule
