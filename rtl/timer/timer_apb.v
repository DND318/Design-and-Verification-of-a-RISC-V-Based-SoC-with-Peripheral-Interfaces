`timescale 1ns/1ps
// APB4 timer (RISC-V mtime/mtimecmp). 64-bit up counter {TDR1,TDR0} that
// increments once per tick while TCR.timer_en = 1; a tick is every clock when
// TCR.div_en = 0 and every 2^div_val clocks when TCR.div_en = 1 (div_val 0..8).
// TISR.cmp_match = ({TDR1,TDR0} >= {TCMP1,TCMP0}), unsigned 64-bit.
// irq_mtip_o = TIER.cmp_ie AND cmp_match, registered (one clock after the
// condition changes in the registers).
// Basic level only: no PSLVERR, no lock of TCR while enabled, no counter
// clear on disable. A prohibited div_val (9..15) leaves div_val unchanged.
// A software write to TDR0/TDR1 wins over the increment: in that cycle the
// whole 64-bit counter does not increment; written bytes take PWDATA and all
// other bytes keep their value.
module timer_apb (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire        psel_i,
  input  wire        penable_i,
  input  wire        pwrite_i,
  input  wire [11:0] paddr_i,
  input  wire [31:0] pwdata_i,
  input  wire [3:0]  pstrb_i,
  output reg  [31:0] prdata_o,
  output wire        pready_o,
  output wire        pslverr_o,
  output wire        irq_mtip_o
);

  // Word offsets (paddr_i[11:2])
  localparam [9:0] OFS_TCR   = 10'h000;  // 0x00
  localparam [9:0] OFS_TIER  = 10'h001;  // 0x04
  localparam [9:0] OFS_TISR  = 10'h002;  // 0x08
  localparam [9:0] OFS_TDR0  = 10'h004;  // 0x10
  localparam [9:0] OFS_TDR1  = 10'h005;  // 0x14
  localparam [9:0] OFS_TCMP0 = 10'h006;  // 0x18
  localparam [9:0] OFS_TCMP1 = 10'h007;  // 0x1C

  localparam [3:0] DIV_VAL_MAX = 4'd8;

  // Byte-strobe merge of a 32-bit register.
  function [31:0] strb_merge;
    input [31:0] old_val;
    input [31:0] new_val;
    input [3:0]  strb;
    begin
      strb_merge = {strb[3] ? new_val[31:24] : old_val[31:24],
                    strb[2] ? new_val[23:16] : old_val[23:16],
                    strb[1] ? new_val[15:8]  : old_val[15:8],
                    strb[0] ? new_val[7:0]   : old_val[7:0]};
    end
  endfunction

  reg [3:0]  div_val_q;
  reg        div_en_q;
  reg        timer_en_q;
  reg        cmp_ie_q;
  reg [7:0]  presc_q;
  reg [7:0]  presc_d;
  reg [63:0] cnt_q;
  reg [63:0] cnt_d;
  reg [63:0] cmp_q;
  reg [63:0] cmp_d;
  reg        irq_q;
  reg [7:0]  presc_max;

  wire [9:0] word_addr = paddr_i[11:2];
  wire       wr_acc    = psel_i & penable_i & pwrite_i;
  wire       wr_any    = (pstrb_i != 4'b0000);
  wire       wr_tcr    = wr_acc & (word_addr == OFS_TCR);
  wire       wr_tier   = wr_acc & (word_addr == OFS_TIER);
  wire       wr_tdr0   = wr_acc & (word_addr == OFS_TDR0)  & wr_any;
  wire       wr_tdr1   = wr_acc & (word_addr == OFS_TDR1)  & wr_any;
  wire       wr_tcmp0  = wr_acc & (word_addr == OFS_TCMP0) & wr_any;
  wire       wr_tcmp1  = wr_acc & (word_addr == OFS_TCMP1) & wr_any;

  wire       cmp_match = (cnt_q >= cmp_q);

  // ---------------------------------------------------------------- prescaler
  // Terminal count = 2^div_val - 1; the prescaler restarts from 0 after a tick
  // and is held at 0 while the timer or the divider is disabled.
  always @* begin
    case (div_val_q)
      4'd0:    presc_max = 8'd0;
      4'd1:    presc_max = 8'd1;
      4'd2:    presc_max = 8'd3;
      4'd3:    presc_max = 8'd7;
      4'd4:    presc_max = 8'd15;
      4'd5:    presc_max = 8'd31;
      4'd6:    presc_max = 8'd63;
      4'd7:    presc_max = 8'd127;
      default: presc_max = 8'd255;
    endcase
  end

  wire tick = timer_en_q & (~div_en_q | (presc_q > presc_max));

  always @* begin
    presc_d = presc_q + 8'd1;
    if (!timer_en_q || !div_en_q || tick) presc_d = 8'd0;
  end

  // ---------------------------------------------------------------- counter
  always @* begin
    cnt_d = cnt_q;
    if (wr_tdr0)      cnt_d[31:0]  = strb_merge(cnt_q[31:0],  pwdata_i, pstrb_i);
    else if (wr_tdr1) cnt_d[63:32] = strb_merge(cnt_q[63:32], pwdata_i, pstrb_i);
    else if (tick)    cnt_d        = cnt_q + 64'd1;
  end

  always @* begin
    cmp_d = cmp_q;
    if (wr_tcmp0) cmp_d[31:0]  = strb_merge(cmp_q[31:0],  pwdata_i, pstrb_i);
    if (wr_tcmp1) cmp_d[63:32] = strb_merge(cmp_q[63:32], pwdata_i, pstrb_i);
  end

  // ---------------------------------------------------------------- registers
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      div_val_q  <= 4'd1;
      div_en_q   <= 1'b0;
      timer_en_q <= 1'b0;
      cmp_ie_q   <= 1'b0;
      presc_q    <= 8'd0;
      cnt_q      <= 64'd0;
      cmp_q      <= 64'd0;
      irq_q      <= 1'b0;
    end else begin
      if (wr_tcr && pstrb_i[0]) begin
        div_en_q   <= pwdata_i[1];
        timer_en_q <= pwdata_i[0];
      end
      if (wr_tcr && pstrb_i[1] && (pwdata_i[11:8] <= DIV_VAL_MAX)) begin
        div_val_q <= pwdata_i[11:8];
      end
      if (wr_tier && pstrb_i[0]) begin
        cmp_ie_q <= pwdata_i[0];
      end
      presc_q <= presc_d;
      cnt_q   <= cnt_d;
      cmp_q   <= cmp_d;
      irq_q   <= cmp_ie_q & cmp_match;
    end
  end

  // ---------------------------------------------------------------- read mux
  always @* begin
    prdata_o = 32'd0;
    case (word_addr)
      OFS_TCR:   prdata_o = {20'd0, div_val_q, 6'd0, div_en_q, timer_en_q};
      OFS_TIER:  prdata_o = {31'd0, cmp_ie_q};
      OFS_TISR:  prdata_o = {31'd0, cmp_match};
      OFS_TDR0:  prdata_o = cnt_q[31:0];
      OFS_TDR1:  prdata_o = cnt_q[63:32];
      OFS_TCMP0: prdata_o = cmp_q[31:0];
      OFS_TCMP1: prdata_o = cmp_q[63:32];
      default:   prdata_o = 32'd0;
    endcase
  end

  assign pready_o   = 1'b1;
  assign pslverr_o  = 1'b0;
  assign irq_mtip_o = irq_q;

  wire unused_in = &{1'b0, paddr_i[1:0]};

endmodule
