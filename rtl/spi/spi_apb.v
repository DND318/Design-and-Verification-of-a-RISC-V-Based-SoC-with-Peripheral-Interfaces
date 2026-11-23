`timescale 1ns/1ps
// SPI master, APB4 slave at APB slot 1 (0x1000_1000). Registers per regmap.py
// SPI: CTRL, CLKDIV, CS, STATUS, TXDATA, RXDATA, IER, ISR. 16-byte TX and RX
// FIFOs (sync_fifo, first-word fall-through) around spi_engine.
// - While CTRL.spi_en = 1, bytes in the TX FIFO are sent back to back: the
//   next byte is loaded in the same clock in which the previous frame ends.
//   Clearing spi_en lets the current frame finish; no new frame starts.
// - Every finished frame pushes the received byte into the RX FIFO, or sets
//   ISR.rx_ovr (byte lost) when the RX FIFO is full in that clock.
// - ISR.done sets when a frame ends while the TX FIFO is empty.
// - ISR bits are W1C; a set in the same clock as a clear wins.
// - irq_spi_o = OR(ISR & IER). CS.cs_n drives spi_cs_no directly.
// - TXDATA write while the TX FIFO is full drops the byte (no flag in this
//   register map). RXDATA read while empty returns 0.
// - pready_o = 1, pslverr_o = 0 (advanced (*) checks not built).
// spi_miso_i is synchronized inside spi_engine (sync_2ff); see its header
// for the MISO sampling scheme.
module spi_apb (
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
  output wire        spi_sclk_o,
  output wire        spi_mosi_o,
  input  wire        spi_miso_i,
  output wire        spi_cs_no,
  output wire        irq_spi_o
);

  // Word offsets (paddr_i[11:2])
  localparam [9:0] A_CTRL   = 10'h000;  // 0x00
  localparam [9:0] A_CLKDIV = 10'h001;  // 0x04
  localparam [9:0] A_CS     = 10'h002;  // 0x08
  localparam [9:0] A_STATUS = 10'h003;  // 0x0C
  localparam [9:0] A_TXDATA = 10'h004;  // 0x10
  localparam [9:0] A_RXDATA = 10'h005;  // 0x14
  localparam [9:0] A_IER    = 10'h006;  // 0x18
  localparam [9:0] A_ISR    = 10'h007;  // 0x1C

  wire [9:0] waddr  = paddr_i[11:2];
  wire       wr_acc = psel_i && penable_i && pwrite_i;
  wire       rd_acc = psel_i && penable_i && !pwrite_i;
  wire       wr_b0  = wr_acc && pstrb_i[0];

  // Registers
  reg  [3:0] ctrl_q;    // [3] lsb_first, [2] cpha, [1] cpol, [0] spi_en
  reg  [7:0] clkdiv_q;
  reg        cs_q;
  reg  [1:0] ier_q;     // [1] rx_ovr_ie, [0] done_ie
  reg  [1:0] isr_q;     // [1] rx_ovr,    [0] done
  reg  [1:0] isr_d;

  // FIFOs and engine
  wire [7:0] tx_rdata, rx_rdata, eng_rx;
  wire       tx_full, tx_empty, rx_full, rx_empty;
  wire       rx_ovf;
  wire [4:0] tx_count_unused, rx_count_unused;
  wire       tx_ovf_unused, tx_udf_unused, rx_udf_unused;
  wire       eng_ready, eng_busy, eng_done;

  wire tx_push   = wr_b0 && (waddr == A_TXDATA);
  wire rx_pop    = rd_acc && (waddr == A_RXDATA);
  wire eng_start = ctrl_q[0] && !tx_empty && eng_ready;

  sync_fifo #(.WIDTH(8), .DEPTH(16)) u_tx_fifo (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .wr_en_i     (tx_push),
    .wdata_i     (pwdata_i[7:0]),
    .rd_en_i     (eng_start),
    .rdata_o     (tx_rdata),
    .full_o      (tx_full),
    .empty_o     (tx_empty),
    .count_o     (tx_count_unused),
    .overflow_o  (tx_ovf_unused),
    .underflow_o (tx_udf_unused)
  );

  sync_fifo #(.WIDTH(8), .DEPTH(16)) u_rx_fifo (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .wr_en_i     (eng_done),
    .wdata_i     (eng_rx),
    .rd_en_i     (rx_pop),
    .rdata_o     (rx_rdata),
    .full_o      (rx_full),
    .empty_o     (rx_empty),
    .count_o     (rx_count_unused),
    .overflow_o  (rx_ovf),
    .underflow_o (rx_udf_unused)
  );

  spi_engine u_engine (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .start_i     (eng_start),
    .tx_data_i   (tx_rdata),
    .cpol_i      (ctrl_q[1]),
    .cpha_i      (ctrl_q[2]),
    .lsb_first_i (ctrl_q[3]),
    .clk_div_i   (clkdiv_q),
    .ready_o     (eng_ready),
    .busy_o      (eng_busy),
    .done_o      (eng_done),
    .rx_data_o   (eng_rx),
    .spi_sclk_o  (spi_sclk_o),
    .spi_mosi_o  (spi_mosi_o),
    .spi_miso_i  (spi_miso_i)
  );

  // ISR: event set wins over a W1C clear in the same clock.
  always @* begin
    isr_d = isr_q;
    if (wr_b0 && (waddr == A_ISR)) isr_d = isr_d & ~pwdata_i[1:0];
    if (eng_done)                  isr_d[0] = 1'b1;
    if (rx_ovf)                    isr_d[1] = 1'b1;
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ctrl_q   <= 4'h0;
      clkdiv_q <= 8'd1;
      cs_q     <= 1'b1;
      ier_q    <= 2'b00;
      isr_q    <= 2'b00;
    end else begin
      if (wr_b0 && (waddr == A_CTRL))   ctrl_q   <= pwdata_i[3:0];
      if (wr_b0 && (waddr == A_CLKDIV)) clkdiv_q <= pwdata_i[7:0];
      if (wr_b0 && (waddr == A_CS))     cs_q     <= pwdata_i[0];
      if (wr_b0 && (waddr == A_IER))    ier_q    <= pwdata_i[1:0];
      isr_q <= isr_d;
    end
  end

  // Read data (combinational from registers)
  always @* begin
    prdata_o = 32'd0;
    case (waddr)
      A_CTRL:   prdata_o = {28'd0, ctrl_q};
      A_CLKDIV: prdata_o = {24'd0, clkdiv_q};
      A_CS:     prdata_o = {31'd0, cs_q};
      A_STATUS: prdata_o = {27'd0, rx_empty, rx_full, tx_empty, tx_full, eng_busy};
      A_RXDATA: prdata_o = rx_empty ? 32'd0 : {24'd0, rx_rdata};
      A_IER:    prdata_o = {30'd0, ier_q};
      A_ISR:    prdata_o = {30'd0, isr_q};
      default:  prdata_o = 32'd0;   // TXDATA (WO) and reserved offsets
    endcase
  end

  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;
  assign spi_cs_no = cs_q;
  assign irq_spi_o = |(isr_q & ier_q);

  // Inputs and FIFO outputs not needed by this block.
  wire unused_ok = &{1'b0, paddr_i[1:0], pwdata_i[31:8], pstrb_i[3:1],
                     tx_count_unused, rx_count_unused, tx_ovf_unused,
                     tx_udf_unused, rx_udf_unused};

endmodule
