`timescale 1ns/1ps
// Synchronous FIFO, first-word fall-through.
// rdata_o shows the oldest entry whenever empty_o = 0; rd_en_i pops it.
// A write when full and a read when empty are ignored and flagged by
// overflow_o / underflow_o in the same cycle.
// DEPTH must be a power of two.
module sync_fifo #(
  parameter WIDTH = 8,
  parameter DEPTH = 16
) (
  input  wire                   clk_i,
  input  wire                   rst_ni,
  input  wire                   wr_en_i,
  input  wire [WIDTH-1:0]       wdata_i,
  input  wire                   rd_en_i,
  output wire [WIDTH-1:0]       rdata_o,
  output wire                   full_o,
  output wire                   empty_o,
  output wire [$clog2(DEPTH):0] count_o,
  output wire                   overflow_o,
  output wire                   underflow_o
);

  localparam AW = $clog2(DEPTH);
  localparam [AW:0] FULL_COUNT = DEPTH;

  reg  [WIDTH-1:0] mem_q [0:DEPTH-1];
  reg  [AW-1:0]    wptr_q, rptr_q;
  reg  [AW:0]      count_q;

  wire do_wr = wr_en_i && !full_o;
  wire do_rd = rd_en_i && !empty_o;

  assign full_o      = (count_q == FULL_COUNT);
  assign empty_o     = (count_q == {(AW+1){1'b0}});
  assign overflow_o  = wr_en_i && full_o;
  assign underflow_o = rd_en_i && empty_o;
  assign rdata_o     = mem_q[rptr_q];
  assign count_o     = count_q;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wptr_q  <= {AW{1'b0}};
      rptr_q  <= {AW{1'b0}};
      count_q <= {(AW+1){1'b0}};
    end else begin
      if (do_wr) wptr_q <= wptr_q + 1'b1;
      if (do_rd) rptr_q <= rptr_q + 1'b1;
      case ({do_wr, do_rd})
        2'b10:   count_q <= count_q + 1'b1;
        2'b01:   count_q <= count_q - 1'b1;
        default: count_q <= count_q;
      endcase
    end
  end

  // Storage has no reset so it can map to RAM.
  always @(posedge clk_i) begin
    if (do_wr) mem_q[wptr_q] <= wdata_i;
  end

endmodule
