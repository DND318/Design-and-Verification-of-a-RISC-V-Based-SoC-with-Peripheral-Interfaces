`timescale 1ns/1ps
// APB4 interrupt controller. Collects the level interrupts of UART (bit 0),
// SPI (bit 1), I2C (bit 2) and GPIO (bit 3), masks them with IRQ_ENABLE and
// drives irq_meip_o = |(IRQ_PENDING & IRQ_ENABLE). IRQ_ID = index of the
// lowest set bit of IRQ_STATUS plus 1 (0 = none). IRQ_ENABLE is the only
// state; the inputs come from on-chip blocks in the same clock domain, so no
// synchronizer is used. Basic level only: no PSLVERR.
module irqc_apb (
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
  input  wire        irq_uart_i,
  input  wire        irq_spi_i,
  input  wire        irq_i2c_i,
  input  wire        irq_gpio_i,
  output wire        irq_meip_o
);

  // Word offsets (paddr_i[11:2])
  localparam [9:0] OFS_PENDING = 10'h000;  // 0x00
  localparam [9:0] OFS_ENABLE  = 10'h001;  // 0x04
  localparam [9:0] OFS_STATUS  = 10'h002;  // 0x08
  localparam [9:0] OFS_ID      = 10'h003;  // 0x0C

  reg  [3:0] enable_q;

  wire [9:0] word_addr = paddr_i[11:2];
  wire       wr_enable = psel_i & penable_i & pwrite_i & (word_addr == OFS_ENABLE) & pstrb_i[0];
  wire [3:0] pending   = {irq_gpio_i, irq_i2c_i, irq_spi_i, irq_uart_i};
  wire [3:0] status    = pending & enable_q;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 4'd0;
    end else if (wr_enable) begin
      enable_q <= pwdata_i[3:0];
    end
  end

  // Fixed priority: bit 0 (UART) highest. Continuous assignment, so the
  // value is defined from time 0 in every simulator.
  wire [2:0] irq_id = status[0] ? 3'd1 :
                      status[1] ? 3'd2 :
                      status[2] ? 3'd3 :
                      status[3] ? 3'd4 : 3'd0;

  always @* begin
    prdata_o = 32'd0;
    case (word_addr)
      OFS_PENDING: prdata_o = {28'd0, pending};
      OFS_ENABLE:  prdata_o = {28'd0, enable_q};
      OFS_STATUS:  prdata_o = {28'd0, status};
      OFS_ID:      prdata_o = {29'd0, irq_id};
      default:     prdata_o = 32'd0;
    endcase
  end

  assign pready_o   = 1'b1;
  assign pslverr_o  = 1'b0;
  assign irq_meip_o = |pending;

  wire unused_in = &{1'b0, paddr_i[1:0], pwdata_i[31:4], pstrb_i[3:1]};

endmodule
