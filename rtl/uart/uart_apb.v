`timescale 1ns/1ps
module uart_apb (
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
  output wire        uart_tx_o,
  input  wire        uart_rx_i,
  output wire        irq_uart_o
);

  // Word offsets (paddr_i[11:2])
  localparam [9:0] A_CTRL   = 10'd0;
  localparam [9:0] A_BAUD   = 10'd1;
  localparam [9:0] A_STATUS = 10'd2;
  localparam [9:0] A_TXDATA = 10'd3;
  localparam [9:0] A_RXDATA = 10'd4;
  localparam [9:0] A_IER    = 10'd5;
  localparam [9:0] A_ISR    = 10'd6;

  localparam [15:0] BAUD_RST = 16'd433;

  // ---------------------------------------------------------------- APB decode
  wire [9:0] waddr  = paddr_i[11:2];
  wire       wr_acc = psel_i && penable_i && pwrite_i;
  wire       rd_acc = psel_i && penable_i && !pwrite_i;

  wire wr_ctrl   = wr_acc && (waddr == A_CTRL);
  wire wr_baud   = wr_acc && (waddr == A_BAUD);
  wire wr_txdata = wr_acc && (waddr == A_TXDATA) && pstrb_i[0];
  wire wr_ier    = wr_acc && (waddr == A_IER);
  wire wr_isr    = wr_acc && (waddr == A_ISR) && pstrb_i[0];
  wire rd_rxdata = rd_acc && (waddr == A_RXDATA);

  // ---------------------------------------------------------------- registers
  reg        tx_en_q, rx_en_q, stop2_q, loopback_q;
  reg [1:0]  parity_q;
  reg [15:0] baud_q;
  reg [5:0]  ier_q;
  reg        tx_ovf_q, overrun_q, frame_err_q, parity_err_q;

  // ---------------------------------------------------------------- datapath
  wire       rx_sync;
  wire       rx_line;
  wire       tx_ser;

  wire [7:0] tx_fifo_rdata;
  wire       tx_fifo_full, tx_fifo_empty, tx_fifo_ovf;
  wire       tx_accept, tx_busy;

  wire [7:0] rx_data, rx_fifo_rdata;
  wire       rx_valid, rx_perr, rx_ferr, rx_busy;
  wire       rx_fifo_full, rx_fifo_empty, rx_fifo_ovf;

  wire [4:0] unused_tx_count, unused_rx_count;
  wire       unused_tx_udf, unused_rx_udf;

  sync_2ff #(.WIDTH(1), .RESET_VAL(1)) u_rx_sync (
    .clk_i (clk_i),
    .rst_ni(rst_ni),
    .d_i   (uart_rx_i),
    .q_o   (rx_sync)
  );

  sync_fifo #(.WIDTH(8), .DEPTH(16)) u_tx_fifo (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .wr_en_i    (wr_txdata),
    .wdata_i    (pwdata_i[7:0]),
    .rd_en_i    (tx_accept),
    .rdata_o    (tx_fifo_rdata),
    .full_o     (tx_fifo_full),
    .empty_o    (tx_fifo_empty),
    .count_o    (unused_tx_count),
    .overflow_o (tx_fifo_ovf),
    .underflow_o(unused_tx_udf)
  );

  uart_tx u_tx (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .baud_div_i(baud_q),
    .parity_i  (parity_q),
    .stop2_i   (stop2_q),
    .valid_i   (tx_en_q && !tx_fifo_empty),
    .data_i    (tx_fifo_rdata),
    .accept_o  (tx_accept),
    .busy_o    (tx_busy),
    .tx_o      (tx_ser)
  );

  assign rx_line   = loopback_q ? tx_ser : rx_sync;
  assign uart_tx_o = loopback_q ? 1'b1 : tx_ser;

  uart_rx u_rx (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .baud_div_i  (baud_q),
    .parity_i    (parity_q),
    .stop2_i     (stop2_q),
    .en_i        (rx_en_q),
    .rx_i        (rx_line),
    .valid_o     (rx_valid),
    .data_o      (rx_data),
    .parity_err_o(rx_perr),
    .frame_err_o (rx_ferr),
    .busy_o      (rx_busy)
  );

  // A frame received while the RX FIFO is full is dropped (overflow_o).
  sync_fifo #(.WIDTH(8), .DEPTH(16)) u_rx_fifo (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .wr_en_i    (rx_valid),
    .wdata_i    (rx_data),
    .rd_en_i    (rd_rxdata),
    .rdata_o    (rx_fifo_rdata),
    .full_o     (rx_fifo_full),
    .empty_o    (rx_fifo_empty),
    .count_o    (unused_rx_count),
    .overflow_o (rx_fifo_ovf),
    .underflow_o(unused_rx_udf)
  );

  // ---------------------------------------------------------------- register writes
  wire [3:0] isr_clr = wr_isr ? pwdata_i[5:2] : 4'd0;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tx_en_q      <= 1'b0;
      rx_en_q      <= 1'b0;
      parity_q     <= 2'b00;
      stop2_q      <= 1'b0;
      loopback_q   <= 1'b0;
      baud_q       <= BAUD_RST;
      ier_q        <= 6'd0;
      tx_ovf_q     <= 1'b0;
      overrun_q    <= 1'b0;
      frame_err_q  <= 1'b0;
      parity_err_q <= 1'b0;
    end else begin
      if (wr_ctrl && pstrb_i[0]) begin
        tx_en_q    <= pwdata_i[0];
        rx_en_q    <= pwdata_i[1];
        stop2_q    <= pwdata_i[4];
        loopback_q <= pwdata_i[5];
        if (pwdata_i[3:2] != 2'b11) begin
          parity_q <= pwdata_i[3:2];
        end
      end
      if (wr_baud && pstrb_i[0]) baud_q[7:0]  <= pwdata_i[7:0];
      if (wr_baud && pstrb_i[1]) baud_q[15:8] <= pwdata_i[15:8];
      if (wr_ier && pstrb_i[0])  ier_q        <= pwdata_i[5:0];

      // W1C event flags: a new event in the same cycle wins over the clear.
      tx_ovf_q     <= tx_fifo_ovf                 | (tx_ovf_q     & ~isr_clr[3]);
      overrun_q    <= rx_fifo_ovf                 | (overrun_q    & ~isr_clr[2]);
      frame_err_q  <= (rx_valid && rx_ferr)       | (frame_err_q  & ~isr_clr[1]);
      parity_err_q <= (rx_valid && rx_perr)       | (parity_err_q & ~isr_clr[0]);
    end
  end

  // ---------------------------------------------------------------- read mux
  wire [5:0] isr_val = {tx_ovf_q, overrun_q, frame_err_q, parity_err_q,
                        !rx_fifo_empty, tx_fifo_empty};

  always @* begin
    prdata_o = 32'd0;
    case (waddr)
      A_CTRL:   prdata_o = {26'd0, loopback_q, stop2_q, parity_q, rx_en_q, tx_en_q};
      A_BAUD:   prdata_o = {16'd0, baud_q};
      A_STATUS: prdata_o = {26'd0, rx_busy, tx_busy, rx_fifo_empty, rx_fifo_full,
                            tx_fifo_empty, tx_fifo_full};
      A_RXDATA: prdata_o = {24'd0, (rx_fifo_empty ? 8'd0 : rx_fifo_rdata)};
      A_IER:    prdata_o = {26'd0, ier_q};
      A_ISR:    prdata_o = {26'd0, isr_val};
      default:  prdata_o = 32'd0;
    endcase
  end

  assign pready_o   = 1'b1;
  assign pslverr_o  = 1'b0;
  assign irq_uart_o = |(isr_val & ier_q);

  // Bits of the APB bus that no register uses.
  wire unused_apb = ^{paddr_i[1:0], pwdata_i[31:16], pstrb_i[3:2]};

endmodule
