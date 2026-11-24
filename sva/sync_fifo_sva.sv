`timescale 1ns/1ps
// Assertions for sync_fifo. Attached with bind in sync_fifo_bind.sv.
module sync_fifo_sva #(
  parameter int unsigned WIDTH = 8,
  parameter int unsigned DEPTH = 16
) (
  input logic                   clk_i,
  input logic                   rst_ni,
  input logic                   wr_en_i,
  input logic                   rd_en_i,
  input logic                   full_o,
  input logic                   empty_o,
  input logic [$clog2(DEPTH):0] count_o,
  input logic                   overflow_o,
  input logic                   underflow_o
);

  a_not_full_and_empty: assert property (@(posedge clk_i) disable iff (!rst_ni)
    !(full_o && empty_o))
    else $error("SVA: full_o and empty_o are both high");

  a_count_max: assert property (@(posedge clk_i) disable iff (!rst_ni)
    count_o <= ($clog2(DEPTH)+1)'(DEPTH))
    else $error("SVA: count_o %0d exceeds DEPTH", count_o);

  a_full_matches_count: assert property (@(posedge clk_i) disable iff (!rst_ni)
    full_o == (count_o == ($clog2(DEPTH)+1)'(DEPTH)))
    else $error("SVA: full_o does not match count_o");

  a_empty_matches_count: assert property (@(posedge clk_i) disable iff (!rst_ni)
    empty_o == (count_o == '0))
    else $error("SVA: empty_o does not match count_o");

  a_overflow: assert property (@(posedge clk_i) disable iff (!rst_ni)
    overflow_o == (wr_en_i && full_o))
    else $error("SVA: overflow_o wrong");

  a_underflow: assert property (@(posedge clk_i) disable iff (!rst_ni)
    underflow_o == (rd_en_i && empty_o))
    else $error("SVA: underflow_o wrong");

  a_count_inc: assert property (@(posedge clk_i) disable iff (!rst_ni)
    (wr_en_i && !full_o && !(rd_en_i && !empty_o)) |=> (count_o == $past(count_o) + 1'b1))
    else $error("SVA: count_o did not increment on write");

  a_count_dec: assert property (@(posedge clk_i) disable iff (!rst_ni)
    (rd_en_i && !empty_o && !(wr_en_i && !full_o)) |=> (count_o == $past(count_o) - 1'b1))
    else $error("SVA: count_o did not decrement on read");

  a_count_hold: assert property (@(posedge clk_i) disable iff (!rst_ni)
    ((wr_en_i && !full_o) == (rd_en_i && !empty_o)) |=> (count_o == $past(count_o)))
    else $error("SVA: count_o changed without a single push or pop");

endmodule
