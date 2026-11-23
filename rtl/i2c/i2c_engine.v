`timescale 1ns/1ps
// I2C master bit/byte engine (single master, no clock stretching, no arbitration).
// Executes one command: optional START / repeated START, optional byte (write
// TXDATA and read the slave ACK, or read a byte and send ACK/NACK), optional STOP.
// Every SCL bit is four quarter periods of (prescale_i + 1) clocks:
//   q0 SCL low, SDA held | q1 SCL low, SDA changes | q2 SCL high | q3 SCL high, sample at its end
// so f_SCL = f_clk / (4 * (prescale_i + 1)) and SDA only changes while SCL is low,
// one quarter after SCL fell (hold) and one quarter before SCL rises (setup).
// START: q0 release SDA, q1 release SCL, q2 pull SDA low, q3 pull SCL low.
// STOP : q0 SCL low (hold), q1 pull SDA low, q2 release SCL, q3 release SDA (bus free).
// After a byte without STOP: one more quarter with SCL low, then SDA is released
// and SCL stays low until the next command.
// Open-drain outputs: *_oe_o = 1 pulls the line Low, 0 releases it.
module i2c_engine (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire        en_i,          // 0: abort, release both lines, stay idle
  input  wire [15:0] prescale_i,
  input  wire        cmd_valid_i,   // one-cycle command strobe, taken only when idle
  input  wire        cmd_start_i,
  input  wire        cmd_stop_i,
  input  wire        cmd_write_i,
  input  wire        cmd_read_i,
  input  wire        cmd_nack_i,
  input  wire [7:0]  txdata_i,
  input  wire        sda_i,         // synchronized SDA line
  output wire        busy_o,
  output wire        done_o,        // one-cycle pulse: command finished
  output wire        ack_valid_o,   // one-cycle pulse: slave ACK bit of a write sampled
  output wire        ack_nack_o,    // last sampled slave ACK bit (1 = NACK)
  output wire [7:0]  rxdata_o,      // last received byte
  output wire        scl_oe_o,
  output wire        sda_oe_o
);

  localparam [2:0] S_IDLE  = 3'd0;
  localparam [2:0] S_START = 3'd1;
  localparam [2:0] S_BIT   = 3'd2;
  localparam [2:0] S_END   = 3'd3;
  localparam [2:0] S_STOP  = 3'd4;

  reg [2:0]  state_q, state_d;
  reg [1:0]  phase_q, phase_d;     // quarter inside the current state
  reg [3:0]  bitcnt_q, bitcnt_d;   // 0..7 data bits, 8 = ACK bit
  reg [15:0] cnt_q, cnt_d;         // clock counter inside a quarter
  reg [7:0]  shift_q, shift_d;
  reg        stop_q, stop_d;
  reg        write_q, write_d;
  reg        read_q, read_d;
  reg        nack_q, nack_d;
  reg        scl_oe_q, scl_oe_d;
  reg        sda_oe_q, sda_oe_d;
  reg        done_q, done_d;
  reg        ack_valid_q, ack_valid_d;
  reg        ack_nack_q, ack_nack_d;
  reg [7:0]  rxdata_q, rxdata_d;

  wire qtick = (cnt_q >= prescale_i);   // last clock of the current quarter

  always @* begin
    state_d     = state_q;
    phase_d     = phase_q;
    bitcnt_d    = bitcnt_q;
    cnt_d       = cnt_q;
    shift_d     = shift_q;
    stop_d      = stop_q;
    write_d     = write_q;
    read_d      = read_q;
    nack_d      = nack_q;
    scl_oe_d    = scl_oe_q;
    sda_oe_d    = sda_oe_q;
    done_d      = 1'b0;
    ack_valid_d = 1'b0;
    ack_nack_d  = ack_nack_q;
    rxdata_d    = rxdata_q;

    if (!en_i) begin
      state_d  = S_IDLE;
      phase_d  = 2'd0;
      bitcnt_d = 4'd0;
      cnt_d    = 16'd0;
      scl_oe_d = 1'b0;
      sda_oe_d = 1'b0;
    end else if (state_q == S_IDLE) begin
      phase_d  = 2'd0;
      bitcnt_d = 4'd0;
      cnt_d    = 16'd0;
      if (cmd_valid_i) begin
        stop_d  = cmd_stop_i;
        write_d = cmd_write_i;
        read_d  = cmd_read_i;
        nack_d  = cmd_nack_i;
        shift_d = txdata_i;
        if (cmd_start_i) begin
          state_d  = S_START;
          sda_oe_d = 1'b0;                 // START q0: release SDA, SCL unchanged
        end else if (cmd_write_i || cmd_read_i) begin
          state_d  = S_BIT;
          scl_oe_d = 1'b1;                 // bit q0: SCL low
        end else if (cmd_stop_i) begin
          state_d  = S_STOP;
          scl_oe_d = 1'b1;                 // STOP q0: SCL low
        end
      end
    end else if (!qtick) begin
      cnt_d = cnt_q + 16'd1;
    end else begin
      cnt_d   = 16'd0;
      phase_d = phase_q + 2'd1;
      case (state_q)
        S_START: begin
          case (phase_q)
            2'd0: scl_oe_d = 1'b0;         // q1: release SCL (SDA high)
            2'd1: sda_oe_d = 1'b1;         // q2: SDA falls while SCL high = START
            2'd2: scl_oe_d = 1'b1;         // q3: SCL low
            default: begin
              if (write_q || read_q) begin
                state_d  = S_BIT;
                bitcnt_d = 4'd0;
              end else if (stop_q) begin
                state_d = S_STOP;
              end else begin
                state_d = S_IDLE;
                done_d  = 1'b1;
              end
            end
          endcase
        end
        S_BIT: begin
          case (phase_q)
            2'd0: begin                    // q1: put the bit on SDA
              if (bitcnt_q == 4'd8)
                sda_oe_d = read_q & nack_q;             // master ACK on read, release on write
              else
                sda_oe_d = write_q & ~shift_q[7];       // data bit on write, release on read
            end
            2'd1: scl_oe_d = 1'b0;         // q2: SCL high
            2'd2: scl_oe_d = 1'b0;         // q3: SCL stays high
            default: begin                 // end of q3: sample SDA, SCL low
              scl_oe_d = 1'b1;
              if (bitcnt_q == 4'd8) begin
                if (write_q) begin
                  ack_valid_d = 1'b1;
                  ack_nack_d  = sda_i;
                end else begin
                  rxdata_d = shift_q;
                end
                state_d = stop_q ? S_STOP : S_END;
              end else begin
                shift_d  = {shift_q[6:0], sda_i};
                bitcnt_d = bitcnt_q + 4'd1;
              end
            end
          endcase
        end
        S_END: begin                       // one quarter of SCL low after the ACK bit
          sda_oe_d = 1'b0;
          phase_d  = 2'd0;
          state_d  = S_IDLE;
          done_d   = 1'b1;
        end
        S_STOP: begin
          case (phase_q)
            2'd0: sda_oe_d = 1'b1;         // q1: SDA low while SCL low
            2'd1: scl_oe_d = 1'b0;         // q2: SCL high
            2'd2: sda_oe_d = 1'b0;         // q3: SDA rises while SCL high = STOP
            default: begin                 // end of q3 (bus free time)
              state_d = S_IDLE;
              done_d  = 1'b1;
            end
          endcase
        end
        default: begin
          state_d  = S_IDLE;
          phase_d  = 2'd0;
          scl_oe_d = 1'b0;
          sda_oe_d = 1'b0;
        end
      endcase
    end
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q     <= S_IDLE;
      phase_q     <= 2'd0;
      bitcnt_q    <= 4'd0;
      cnt_q       <= 16'd0;
      shift_q     <= 8'd0;
      stop_q      <= 1'b0;
      write_q     <= 1'b0;
      read_q      <= 1'b0;
      nack_q      <= 1'b0;
      scl_oe_q    <= 1'b0;
      sda_oe_q    <= 1'b0;
      done_q      <= 1'b0;
      ack_valid_q <= 1'b0;
      ack_nack_q  <= 1'b0;
      rxdata_q    <= 8'd0;
    end else begin
      state_q     <= state_d;
      phase_q     <= phase_d;
      bitcnt_q    <= bitcnt_d;
      cnt_q       <= cnt_d;
      shift_q     <= shift_d;
      stop_q      <= stop_d;
      write_q     <= write_d;
      read_q      <= read_d;
      nack_q      <= nack_d;
      scl_oe_q    <= scl_oe_d;
      sda_oe_q    <= sda_oe_d;
      done_q      <= done_d;
      ack_valid_q <= ack_valid_d;
      ack_nack_q  <= ack_nack_d;
      rxdata_q    <= rxdata_d;
    end
  end

  assign busy_o      = (state_q != S_IDLE);
  assign done_o      = done_q;
  assign ack_valid_o = ack_valid_q;
  assign ack_nack_o  = ack_nack_q;
  assign rxdata_o    = rxdata_q;
  assign scl_oe_o    = scl_oe_q;
  assign sda_oe_o    = sda_oe_q;

endmodule
