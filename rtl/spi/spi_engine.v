`timescale 1ns/1ps
// SPI master shift engine: one full-duplex 8-bit frame per start_i, mode 0-3
// (cpol_i, cpha_i), MSB or LSB first. cpha, lsb_first and clk_div are latched
// when a frame starts, and SCLK follows cpol_i only while idle, so a register
// change while busy affects only the next frame.
//
// SCLK: half period = clk_div + 1 clocks, f_SCLK = f_clk / (2 x (clk_div + 1)).
// SCLK idles at CPOL. A frame is: one half period with SCLK idle, then 16 SCLK
// edges one half period apart, then a short tail (see MISO below).
//   CPHA = 0: MOSI shows bit 0 when the frame starts (one half period before
//             the first edge), is sampled on odd edges 1,3..15 and changes on
//             even edges 2..14.
//   CPHA = 1: MOSI changes on odd edges 1,3..15 and is sampled on even edges
//             2,4..16.
//
// MISO timing: spi_miso_i passes the 2-FF synchronizer (sync_2ff) here, so
// the synchronized value at clock n is the pin value seen at clock edge n-2.
// When the engine launches a sampling SCLK edge at clock edge k, it marks a
// sample in a 2-stage pipeline (pend_q) and shifts the synchronized MISO into
// the RX register at clock edge k+2. That value is the pin as it was at clock
// edge k, i.e. exactly at the sampling SCLK edge (before a slave can react to
// it). The data is therefore taken in the middle of its valid window, which
// runs from the slave's previous shift edge (k - half period) to its next
// shift edge (k + half period). This holds for every clk_div including 0
// (half period of one clock) with a slave that changes MISO right after its
// shift edge. Cost: the frame ends at most 3 clocks after the 16th edge,
// when the last sample has left the pipeline.
//
// Handshake: ready_o = 1 when a new frame may start (idle, or the clock in
// which the current frame ends: done_o = 1). start_i && ready_o loads
// tx_data_i. done_o is a one-clock pulse with the received byte on rx_data_o.
module spi_engine (
  input  wire       clk_i,
  input  wire       rst_ni,
  input  wire       start_i,
  input  wire [7:0] tx_data_i,
  input  wire       cpol_i,
  input  wire       cpha_i,
  input  wire       lsb_first_i,
  input  wire [7:0] clk_div_i,
  output wire       ready_o,
  output wire       busy_o,
  output wire       done_o,
  output wire [7:0] rx_data_o,
  output wire       spi_sclk_o,
  output wire       spi_mosi_o,
  input  wire       spi_miso_i
);

  localparam [1:0] ST_IDLE = 2'd0;
  localparam [1:0] ST_XFER = 2'd1;
  localparam [1:0] ST_TAIL = 2'd2;

  reg  [1:0] state_q, state_d;
  reg  [7:0] div_cnt_q, div_cnt_d;
  reg  [3:0] edge_cnt_q, edge_cnt_d;   // edges already made in this frame (0..15)
  reg        sclk_q, sclk_d;
  reg        mosi_q, mosi_d;
  reg  [7:0] tx_sh_q, tx_sh_d;
  reg  [7:0] rx_sh_q, rx_sh_d;
  reg  [1:0] pend_q, pend_d;           // MISO sample pipeline, see header
  reg        cpha_q, cpha_d;
  reg        lsb_q, lsb_d;
  reg  [7:0] div_q, div_d;

  wire       miso_sync;
  wire       half_done   = (div_cnt_q == div_q);
  wire       sample_edge = (edge_cnt_q[0] == cpha_q);
  wire       last_edge   = (edge_cnt_q == 4'd15);
  wire       done        = (state_q == ST_TAIL) && (pend_q == 2'b00);
  wire       ready       = (state_q == ST_IDLE) || done;

  sync_2ff #(.WIDTH(1), .RESET_VAL(0)) u_miso_sync (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .d_i    (spi_miso_i),
    .q_o    (miso_sync)
  );

  always @* begin
    state_d    = state_q;
    div_cnt_d  = div_cnt_q;
    edge_cnt_d = edge_cnt_q;
    sclk_d     = sclk_q;
    mosi_d     = mosi_q;
    tx_sh_d    = tx_sh_q;
    rx_sh_d    = rx_sh_q;
    pend_d     = {pend_q[0], 1'b0};
    cpha_d     = cpha_q;
    lsb_d      = lsb_q;
    div_d      = div_q;

    // Shift in the MISO bit sampled two clocks ago.
    if (pend_q[1]) begin
      if (lsb_q) rx_sh_d = {rx_sh_q[6:0], miso_sync};
      else       rx_sh_d = {rx_sh_q[6:0], miso_sync};
    end

    case (state_q)
      ST_XFER: begin
        if (half_done) begin
          div_cnt_d  = 8'd0;
          sclk_d     = ~sclk_q;
          edge_cnt_d = edge_cnt_q + 4'd1;
          if (sample_edge) begin
            pend_d[0] = 1'b1;
          end else if (!last_edge) begin
            mosi_d = lsb_q ? tx_sh_q[0] : tx_sh_q[7];
            tx_sh_d = lsb_q ? {1'b0, tx_sh_q[7:1]} : {tx_sh_q[6:0], 1'b0};
          end
          if (last_edge) state_d = ST_TAIL;
        end else begin
          div_cnt_d = div_cnt_q + 8'd1;
        end
      end
      ST_TAIL: begin
        if (done) state_d = ST_IDLE;
      end
      default: begin
        // Idle: SCLK follows CPOL.
        sclk_d = cpol_i;
      end
    endcase

    if (start_i && ready) begin
      state_d    = ST_XFER;
      div_cnt_d  = 8'd0;
      edge_cnt_d = 4'd0;
      sclk_d     = cpol_i;
      cpha_d     = cpha_i;
      lsb_d      = lsb_first_i;
      div_d      = clk_div_i;
      if (cpha_i) begin
        tx_sh_d = tx_data_i;
      end else begin
        // CPHA = 0: first bit is set up one half period before edge 1.
        mosi_d  = lsb_first_i ? tx_data_i[0] : tx_data_i[7];
        tx_sh_d = lsb_first_i ? {1'b0, tx_data_i[7:1]} : {tx_data_i[6:0], 1'b0};
      end
    end
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q    <= ST_IDLE;
      div_cnt_q  <= 8'd0;
      edge_cnt_q <= 4'd0;
      sclk_q     <= 1'b0;
      mosi_q     <= 1'b0;
      tx_sh_q    <= 8'd0;
      rx_sh_q    <= 8'd0;
      pend_q     <= 2'b00;
      cpha_q     <= 1'b0;
      lsb_q      <= 1'b0;
      div_q      <= 8'd0;
    end else begin
      state_q    <= state_d;
      div_cnt_q  <= div_cnt_d;
      edge_cnt_q <= edge_cnt_d;
      sclk_q     <= sclk_d;
      mosi_q     <= mosi_d;
      tx_sh_q    <= tx_sh_d;
      rx_sh_q    <= rx_sh_d;
      pend_q     <= pend_d;
      cpha_q     <= cpha_d;
      lsb_q      <= lsb_d;
      div_q      <= div_d;
    end
  end

  assign ready_o    = ready;
  assign busy_o     = (state_q != ST_IDLE);
  assign done_o     = done;
  assign rx_data_o  = rx_sh_q;
  assign spi_sclk_o = sclk_q;
  assign spi_mosi_o = mosi_q;

endmodule
