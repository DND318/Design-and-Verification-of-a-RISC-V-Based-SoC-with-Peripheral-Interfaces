`timescale 1ns/1ps
module rv32_muldiv (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire        start_i,
  input  wire [2:0]  funct3_i,
  input  wire [31:0] a_i,
  input  wire [31:0] b_i,
  output wire        done_o,
  output wire [31:0] result_o
);

  // ---------------- multiplier ----------------
  // funct3: 000 MUL, 001 MULH, 010 MULHSU, 011 MULHU
  wire               a_signed = (funct3_i[1:0] != 2'b11);
  wire               b_signed = (funct3_i[1:0] == 2'b01);
  wire signed [32:0] mul_a    = {a_signed & a_i[31], a_i};
  wire signed [32:0] mul_b    = {b_signed & b_i[31], b_i};
  wire signed [63:0] product  = mul_a * mul_b;   // exact low 64 bits of the 66-bit product
  wire        [31:0] mul_result = (funct3_i[1:0] == 2'b00) ? product[31:0] : product[63:32];

  // ---------------- divider ----------------
  // funct3: 100 DIV, 101 DIVU, 110 REM, 111 REMU
  wire        div_signed = ~funct3_i[0];
  wire        want_rem   = funct3_i[1];
  wire [31:0] a_abs      = (div_signed && a_i[31]) ? (~a_i + 32'd1) : a_i;
  wire [31:0] b_abs      = (div_signed && b_i[31]) ? (~b_i + 32'd1) : b_i;

  reg        busy_q;
  reg [5:0]  cnt_q;
  reg [31:0] rem_q, quo_q, dvsr_q;
  reg        neg_quo_q, neg_rem_q, want_rem_q;
  reg        done_q;
  reg [31:0] result_q;

  wire [32:0] shifted  = {rem_q, quo_q[31]};
  wire        ge       = (shifted >= {1'b0, dvsr_q});
  wire [31:0] rem_next = ge ? (shifted[31:0] - dvsr_q) : shifted[31:0];

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      busy_q     <= 1'b0;
      cnt_q      <= 6'd0;
      rem_q      <= 32'd0;
      quo_q      <= 32'd0;
      dvsr_q     <= 32'd0;
      neg_quo_q  <= 1'b0;
      neg_rem_q  <= 1'b0;
      want_rem_q <= 1'b0;
      done_q     <= 1'b0;
      result_q   <= 32'd0;
    end else begin
      done_q <= 1'b0;
      if (start_i) begin
        if (!funct3_i[2]) begin
          result_q <= mul_result;
          done_q   <= 1'b1;
        end else if (b_i == 32'd0) begin
          // Division by zero: quotient all ones, remainder = dividend
          result_q <= want_rem ? a_i : 32'hFFFF_FFFF;
          done_q   <= 1'b1;
        end else begin
          busy_q     <= 1'b1;
          cnt_q      <= 6'd32;
          rem_q      <= 32'd0;
          quo_q      <= a_abs;
          dvsr_q     <= b_abs;
          neg_quo_q  <= div_signed && (a_i[31] ^ b_i[31]);
          neg_rem_q  <= div_signed && a_i[31];
          want_rem_q <= want_rem;
        end
      end else if (busy_q) begin
        if (cnt_q != 6'd0) begin
          rem_q <= rem_next;
          quo_q <= {quo_q[30:0], ge};
          cnt_q <= cnt_q - 6'd1;
        end else begin
          // Signed overflow (-2^31 / -1) falls out naturally: 0x8000_0000, rem 0
          busy_q <= 1'b0;
          done_q <= 1'b1;
          if (want_rem_q) result_q <= neg_rem_q ? (~rem_q + 32'd1) : rem_q;
          else            result_q <= neg_quo_q ? (~quo_q + 32'd1) : quo_q;
        end
      end
    end
  end

  assign done_o   = done_q;
  assign result_o = result_q;

endmodule
