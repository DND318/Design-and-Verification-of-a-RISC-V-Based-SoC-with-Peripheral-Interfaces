`timescale 1ns/1ps
// APB4 GPIO, 8 pins split into gpio_o / gpio_oe_o / gpio_i.
// GPIO_IN is gpio_i after a 2-FF synchronizer. A rising edge of the
// synchronized input sets the matching GPIO_IS bit when its GPIO_IE bit is 1;
// GPIO_IS is W1C (acts only when PSTRB[0] = 1). If a set and a W1C clear hit
// the same bit in the same cycle, the set wins. irq_gpio_o = |(GPIO_IS & GPIO_IE).
// Basic level only: no PSLVERR.
module gpio_apb (
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
  output wire [7:0]  gpio_o,
  output wire [7:0]  gpio_oe_o,
  input  wire [7:0]  gpio_i,
  output wire        irq_gpio_o
);

  // Word offsets (paddr_i[11:2])
  localparam [9:0] OFS_OUT = 10'h000;  // 0x00
  localparam [9:0] OFS_OE  = 10'h001;  // 0x04
  localparam [9:0] OFS_IN  = 10'h002;  // 0x08
  localparam [9:0] OFS_IE  = 10'h003;  // 0x0C
  localparam [9:0] OFS_IS  = 10'h004;  // 0x10

  reg  [7:0] out_q;
  reg  [7:0] oe_q;
  reg  [7:0] ie_q;
  reg  [7:0] is_q;
  reg  [7:0] is_d;
  reg  [7:0] in_prev_q;
  wire [7:0] in_sync;

  wire [9:0] word_addr = paddr_i[11:2];
  wire       wr_b0     = psel_i & penable_i & pwrite_i & pstrb_i[0];
  wire       wr_out    = wr_b0 & (word_addr == OFS_OUT);
  wire       wr_oe     = wr_b0 & (word_addr == OFS_OE);
  wire       wr_ie     = wr_b0 & (word_addr == OFS_IE);
  wire       wr_is     = wr_b0 & (word_addr == OFS_IS);

  sync_2ff #(
    .WIDTH     (8),
    .RESET_VAL (0)
  ) u_sync_in (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .d_i    (gpio_i),
    .q_o    (in_sync)
  );

  wire [7:0] rise = ~in_sync & in_prev_q;

  // W1C clear first, then set, so a set in the same cycle wins.
  always @* begin
    is_d = is_q;
    if (wr_is) is_d = 8'd0;
    is_d = is_d | (rise & ie_q);
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      out_q     <= 8'd0;
      oe_q      <= 8'd0;
      ie_q      <= 8'd0;
      is_q      <= 8'd0;
      in_prev_q <= 8'd0;
    end else begin
      if (wr_out) out_q <= pwdata_i[7:0];
      if (wr_oe)  oe_q  <= pwdata_i[7:0];
      if (wr_ie)  ie_q  <= pwdata_i[7:0];
      is_q      <= is_d;
      in_prev_q <= in_sync;
    end
  end

  always @* begin
    prdata_o = 32'd0;
    case (word_addr)
      OFS_OUT: prdata_o = {24'd0, out_q};
      OFS_OE:  prdata_o = {24'd0, oe_q};
      OFS_IN:  prdata_o = {24'd0, in_sync};
      OFS_IE:  prdata_o = {24'd0, ie_q};
      OFS_IS:  prdata_o = {24'd0, is_q};
      default: prdata_o = 32'd0;
    endcase
  end

  assign gpio_o     = out_q;
  assign gpio_oe_o  = oe_q;
  assign irq_gpio_o = |(is_q & ie_q);
  assign pready_o   = 1'b1;
  assign pslverr_o  = 1'b0;

  wire unused_in = &{1'b0, paddr_i[1:0], pwdata_i[31:8], pstrb_i[3:1]};

endmodule
