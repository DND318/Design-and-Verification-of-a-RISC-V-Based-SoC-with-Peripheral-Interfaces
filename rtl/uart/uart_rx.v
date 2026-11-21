`timescale 1ns/1ps
module uart_rx (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire [15:0] baud_div_i,
  input  wire [1:0]  parity_i,    // 2'b00 none, 2'b01 even, 2'b10 odd
  input  wire        stop2_i,     // 1: two stop bits
  input  wire        en_i,
  input  wire        rx_i,
  output wire        valid_o,
  output wire [7:0]  data_o,
  output wire        parity_err_o,
  output wire        frame_err_o,
  output wire        busy_o
);

  localparam [2:0] S_IDLE  = 3'd0;
  localparam [2:0] S_START = 3'd1;
  localparam [2:0] S_DATA  = 3'd2;
  localparam [2:0] S_PAR   = 3'd3;
  localparam [2:0] S_STOP  = 3'd4;

  reg [2:0]  state_q, state_d;
  reg [15:0] cnt_q, cnt_d;
  reg [2:0]  bit_q, bit_d;
  reg [7:0]  shift_q, shift_d;
  reg        par_en_q, par_en_d;
  reg        par_odd_q, par_odd_d;
  reg        stop2_q, stop2_d;
  reg        perr_q, perr_d;
  reg        ferr_q, ferr_d;
  reg        valid_q, valid_d;
  reg        rx_prev_q;

  wire [15:0] half    = {1'b0, baud_div_i[15:1]};
  wire        bit_end = (cnt_q >= baud_div_i);

  always @* begin
    state_d   = state_q;
    cnt_d     = cnt_q;
    bit_d     = bit_q;
    shift_d   = shift_q;
    par_en_d  = par_en_q;
    par_odd_d = par_odd_q;
    stop2_d   = stop2_q;
    perr_d    = perr_q;
    ferr_d    = ferr_q;
    valid_d   = 1'b0;

    case (state_q)
      S_IDLE: begin
        cnt_d = 16'd0;
        if (rx_prev_q && !rx_i) begin
          state_d   = S_START;
          bit_d     = 3'd0;
          par_en_d  = parity_i[0] | parity_i[1];
          par_odd_d = parity_i[1];
          stop2_d   = stop2_i;
        end
      end
      S_START: begin
        if (cnt_q >= (half >> 1)) begin
          cnt_d = 16'd0;
          if (rx_i) begin
            state_d = S_IDLE;        // false start (glitch)
          end else begin
            state_d = S_DATA;
            perr_d  = 1'b0;
            ferr_d  = 1'b0;
          end
        end else begin
          cnt_d = cnt_q + 16'd1;
        end
      end
      S_DATA: begin
        if (bit_end) begin
          cnt_d   = 16'd0;
          shift_d = {rx_i, shift_q[7:1]};
          if (bit_q == 3'd7) begin
            bit_d   = 3'd0;
            state_d = par_en_q ? S_PAR : S_STOP;
          end else begin
            bit_d = bit_q + 3'd1;
          end
        end else begin
          cnt_d = cnt_q + 16'd1;
        end
      end
      S_PAR: begin
        if (bit_end) begin
          cnt_d   = 16'd0;
          perr_d  = rx_i ^ (^shift_q) ^ par_odd_q;
          state_d = S_STOP;
          bit_d   = 3'd0;
        end else begin
          cnt_d = cnt_q + 16'd1;
        end
      end
      S_STOP: begin
        if (bit_end) begin
          cnt_d  = 16'd0;
          ferr_d = ferr_q | !rx_i;
          if (!stop2_q || bit_q[0]) begin
            state_d = S_IDLE;
            valid_d = 1'b1;
          end else begin
            bit_d = 3'd1;
          end
        end else begin
          cnt_d = cnt_q + 16'd1;
        end
      end
      default: begin
        state_d = S_IDLE;
        cnt_d   = 16'd0;
      end
    endcase

    if (!en_i) begin
      state_d = S_IDLE;
      cnt_d   = 16'd0;
      valid_d = 1'b0;
    end
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= S_IDLE;
      cnt_q     <= 16'd0;
      bit_q     <= 3'd0;
      shift_q   <= 8'd0;
      par_en_q  <= 1'b0;
      par_odd_q <= 1'b0;
      stop2_q   <= 1'b0;
      perr_q    <= 1'b0;
      ferr_q    <= 1'b0;
      valid_q   <= 1'b0;
      rx_prev_q <= 1'b1;
    end else begin
      state_q   <= state_d;
      cnt_q     <= cnt_d;
      bit_q     <= bit_d;
      shift_q   <= shift_d;
      par_en_q  <= par_en_d;
      par_odd_q <= par_odd_d;
      stop2_q   <= stop2_d;
      perr_q    <= perr_d;
      ferr_q    <= ferr_d;
      valid_q   <= valid_d;
      rx_prev_q <= rx_i;
    end
  end

  assign valid_o      = valid_q;
  assign data_o       = shift_q;
  assign parity_err_o = perr_q;
  assign frame_err_o  = ferr_q;
  assign busy_o       = (state_q != S_IDLE);

endmodule
