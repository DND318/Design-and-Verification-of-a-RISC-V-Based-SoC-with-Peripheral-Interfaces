`timescale 1ns/1ps
module uart_tx (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire [15:0] baud_div_i,
  input  wire [1:0]  parity_i,    // 2'b00 none, 2'b01 even, 2'b10 odd
  input  wire        stop2_i,     // 1: two stop bits
  input  wire        valid_i,     // a byte is available and TX is enabled
  input  wire [7:0]  data_i,
  output reg         accept_o,    // byte on data_i is taken this cycle
  output wire        busy_o,      // a frame is being sent
  output wire        tx_o         // serial output
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
  reg        par_bit_q, par_bit_d;
  reg        par_en_q, par_en_d;
  reg        stop2_q, stop2_d;
  reg        tx_q, tx_d;

  wire bit_end   = (cnt_q >= baud_div_i);
  wire last_stop = (state_q == S_STOP) && bit_end && (!stop2_q || bit_q[0]);

  always @* begin
    state_d   = state_q;
    cnt_d     = cnt_q;
    bit_d     = bit_q;
    shift_d   = shift_q;
    par_bit_d = par_bit_q;
    par_en_d  = par_en_q;
    stop2_d   = stop2_q;
    tx_d      = tx_q;
    accept_o  = 1'b0;

    if (state_q != S_IDLE) begin
      cnt_d = bit_end ? 16'd0 : (cnt_q + 16'd1);
    end

    case (state_q)
      S_IDLE: begin
        tx_d = 1'b1;
      end
      S_START: begin
        if (bit_end) begin
          state_d = S_DATA;
          bit_d   = 3'd0;
          tx_d    = shift_q[0];
          shift_d = {1'b0, shift_q[7:1]};
        end
      end
      S_DATA: begin
        if (bit_end) begin
          if (bit_q == 3'd7) begin
            bit_d = 3'd0;
            if (par_en_q) begin
              state_d = S_PAR;
              tx_d    = par_bit_q;
            end else begin
              state_d = S_STOP;
              tx_d    = 1'b1;
            end
          end else begin
            bit_d   = bit_q + 3'd1;
            tx_d    = shift_q[0];
            shift_d = {1'b0, shift_q[7:1]};
          end
        end
      end
      S_PAR: begin
        if (bit_end) begin
          state_d = S_STOP;
          bit_d   = 3'd0;
          tx_d    = 1'b1;
        end
      end
      S_STOP: begin
        if (bit_end) begin
          if (!stop2_q || bit_q[0]) begin
            state_d = S_IDLE;
          end else begin
            bit_d = 3'd1;
          end
          tx_d = 1'b1;
        end
      end
      default: begin
        state_d = S_IDLE;
        tx_d    = 1'b1;
      end
    endcase

    // Take the next byte when idle or right at the end of the last stop bit.
    if (valid_i && ((state_q == S_IDLE) || last_stop)) begin
      accept_o  = 1'b1;
      state_d   = S_START;
      cnt_d     = 16'd0;
      bit_d     = 3'd0;
      tx_d      = 1'b0;
      shift_d   = data_i;
      par_en_d  = parity_i[0] | parity_i[1];
      par_bit_d = (^data_i) ^ parity_i[0];   // even: ^data, odd: ~^data
      stop2_d   = stop2_i;
    end
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= S_IDLE;
      cnt_q     <= 16'd0;
      bit_q     <= 3'd0;
      shift_q   <= 8'd0;
      par_bit_q <= 1'b0;
      par_en_q  <= 1'b0;
      stop2_q   <= 1'b0;
      tx_q      <= 1'b1;
    end else begin
      state_q   <= state_d;
      cnt_q     <= cnt_d;
      bit_q     <= bit_d;
      shift_q   <= shift_d;
      par_bit_q <= par_bit_d;
      par_en_q  <= par_en_d;
      stop2_q   <= stop2_d;
      tx_q      <= tx_d;
    end
  end

  assign busy_o = (state_q != S_IDLE);
  assign tx_o   = tx_q;

endmodule
