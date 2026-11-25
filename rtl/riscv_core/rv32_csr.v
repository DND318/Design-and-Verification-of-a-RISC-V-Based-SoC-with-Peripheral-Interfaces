`timescale 1ns/1ps
module rv32_csr (
  input  wire        clk_i,
  input  wire        rst_ni,

  // CSR instruction access (read is combinational, write on clock edge)
  input  wire [11:0] csr_addr_i,
  input  wire        csr_we_i,       // instruction writes (CSRRW, or rs1/zimm != 0)
  input  wire        csr_wr_en_i,    // perform the write this cycle
  input  wire [1:0]  csr_op_i,       // funct3[1:0]: 01 RW, 10 RS, 11 RC
  input  wire [31:0] csr_operand_i,  // rs1 value or zimm
  output reg  [31:0] csr_rdata_o,
  output wire        csr_illegal_o,

  // Trap entry and return
  input  wire        trap_i,
  input  wire        trap_irq_i,
  input  wire [3:0]  trap_code_i,
  input  wire [31:2] trap_epc_i,
  input  wire [31:0] trap_tval_i,
  input  wire        mret_i,
  output wire [31:0] mtvec_o,
  output wire [31:0] mepc_o,

  // Counters
  input  wire        instret_i,

  // Interrupts
  input  wire        irq_mtip_i,
  input  wire        irq_meip_i,
  output wire        irq_pending_o,
  output wire [3:0]  irq_code_o
);

  reg        mstatus_mie_q, mstatus_mpie_q;
  reg        mie_meie_q, mie_mtie_q, mie_msie_q;
  reg [29:0] mtvec_base_q;
  reg [31:0] mscratch_q;
  reg [29:0] mepc_q;
  reg        mcause_irq_q;
  reg [3:0]  mcause_code_q;
  reg [31:0] mtval_q;
  reg [63:0] mcycle_q, minstret_q;

  wire [31:0] mstatus = {19'b0, 2'b11, 3'b0, mstatus_mpie_q, 3'b0, mstatus_mie_q, 3'b0};
  wire [31:0] mie     = {20'b0, mie_meie_q, 3'b0, mie_mtie_q, 3'b0, mie_msie_q, 3'b0};
  wire [31:0] mip     = {20'b0, irq_meip_i, 3'b0, irq_mtip_i, 3'b0, 1'b0, 3'b0};
  wire [31:0] mtvec   = {mtvec_base_q, 2'b00};
  wire [31:0] mepc    = {mepc_q, 2'b00};
  wire [31:0] mcause  = {mcause_irq_q, 27'b0, mcause_code_q};

  // ---------------- read ----------------
  reg implemented;

  always @* begin
    implemented = 1'b1;
    case (csr_addr_i)
      `RV32_CSR_MSTATUS:   csr_rdata_o = mstatus;
      `RV32_CSR_MISA:      csr_rdata_o = `RV32_MISA_VALUE;
      `RV32_CSR_MIE:       csr_rdata_o = mie;
      `RV32_CSR_MTVEC:     csr_rdata_o = mtvec;
      `RV32_CSR_MSCRATCH:  csr_rdata_o = mscratch_q;
      `RV32_CSR_MEPC:      csr_rdata_o = mepc;
      `RV32_CSR_MCAUSE:    csr_rdata_o = mcause;
      `RV32_CSR_MTVAL:     csr_rdata_o = mtval_q;
      `RV32_CSR_MIP:       csr_rdata_o = mip;
      `RV32_CSR_MCYCLE:    csr_rdata_o = mcycle_q[31:0];
      `RV32_CSR_MCYCLEH:   csr_rdata_o = mcycle_q[63:32];
      `RV32_CSR_MINSTRET:  csr_rdata_o = minstret_q[31:0];
      `RV32_CSR_MINSTRETH: csr_rdata_o = minstret_q[63:32];
      // Zicntr: read-only (address bits [11:10] = 2'b11, a write is illegal)
      `RV32_CSR_CYCLE:     csr_rdata_o = mcycle_q[31:0];
      `RV32_CSR_CYCLEH:    csr_rdata_o = mcycle_q[63:32];
      `RV32_CSR_INSTRET:   csr_rdata_o = minstret_q[31:0];
      `RV32_CSR_INSTRETH:  csr_rdata_o = minstret_q[63:32];
      `RV32_CSR_MVENDORID, `RV32_CSR_MARCHID,
      `RV32_CSR_MIMPID,    `RV32_CSR_MHARTID: csr_rdata_o = 32'd0;
      default: begin
        csr_rdata_o = 32'd0;
        implemented = 1'b0;
      end
    endcase
  end

  assign csr_illegal_o = !implemented || (csr_we_i && (csr_addr_i[11:10] == 2'b11));

  // ---------------- write data ----------------
  reg [31:0] wdata;

  always @* begin
    case (csr_op_i)
      2'b01:   wdata = csr_operand_i;
      2'b10:   wdata = csr_rdata_o | csr_operand_i;
      2'b11:   wdata = csr_rdata_o & ~csr_operand_i;
      default: wdata = csr_rdata_o;
    endcase
  end

  wire wr = csr_wr_en_i && csr_we_i && !csr_illegal_o;

  // ---------------- state ----------------
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mstatus_mie_q  <= 1'b0;
      mstatus_mpie_q <= 1'b0;
      mie_meie_q     <= 1'b0;
      mie_mtie_q     <= 1'b0;
      mie_msie_q     <= 1'b0;
      mtvec_base_q   <= 30'd0;
      mscratch_q     <= 32'd0;
      mepc_q         <= 30'd0;
      mcause_irq_q   <= 1'b0;
      mcause_code_q  <= 4'd0;
      mtval_q        <= 32'd0;
    end else if (trap_i) begin
      mstatus_mpie_q <= mstatus_mie_q;
      mstatus_mie_q  <= 1'b0;
      mepc_q         <= trap_epc_i;
      mcause_irq_q   <= trap_irq_i;
      mcause_code_q  <= trap_code_i;
      mtval_q        <= trap_tval_i;
    end else if (mret_i) begin
      mstatus_mie_q  <= mstatus_mpie_q;
      mstatus_mpie_q <= 1'b1;
    end else if (wr) begin
      case (csr_addr_i)
        `RV32_CSR_MSTATUS: begin
          mstatus_mie_q  <= wdata[3];
          mstatus_mpie_q <= wdata[7];
        end
        `RV32_CSR_MIE: begin
          mie_meie_q <= wdata[11];
          mie_mtie_q <= wdata[7];
          mie_msie_q <= wdata[3];
        end
        `RV32_CSR_MTVEC:    mtvec_base_q <= wdata[31:2];
        `RV32_CSR_MSCRATCH: mscratch_q   <= wdata;
        `RV32_CSR_MEPC:     mepc_q       <= wdata[31:2];
        `RV32_CSR_MCAUSE: begin
          mcause_irq_q  <= wdata[31];
          mcause_code_q <= wdata[3:0];
        end
        `RV32_CSR_MTVAL:    mtval_q      <= wdata;
        default: ;  // misa, mip and counters: no effect here
      endcase
    end
  end

  // Counters: a CSR write has priority over the increment of the same cycle
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mcycle_q   <= 64'd0;
      minstret_q <= 64'd0;
    end else begin
      if (wr && csr_addr_i == `RV32_CSR_MCYCLE)       mcycle_q[31:0]  <= wdata;
      else if (wr && csr_addr_i == `RV32_CSR_MCYCLEH) mcycle_q[63:32] <= wdata;
      else                                            mcycle_q        <= mcycle_q + 64'd1;

      if (wr && csr_addr_i == `RV32_CSR_MINSTRET)       minstret_q[31:0]  <= wdata;
      else if (wr && csr_addr_i == `RV32_CSR_MINSTRETH) minstret_q[63:32] <= wdata;
      else if (instret_i)                               minstret_q        <= minstret_q + 64'd1;
    end
  end

  // ---------------- interrupts ----------------
  wire mei = mie_meie_q && irq_meip_i;
  wire mti = mie_mtie_q && irq_mtip_i;

  assign irq_pending_o = mstatus_mie_q && (mei || mti);
  assign irq_code_o    = mei ? `RV32_IRQ_M_EXTERNAL : `RV32_IRQ_M_TIMER;

  assign mtvec_o = mtvec;
  assign mepc_o  = mepc;

endmodule
