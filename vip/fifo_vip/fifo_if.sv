`timescale 1ns/1ps
interface fifo_if (input logic clk, input logic rst_n);
  localparam int unsigned WIDTH = 8;
  localparam int unsigned DEPTH = 16;

  logic                   wr_en;
  logic                   rd_en;
  logic [WIDTH-1:0]       wdata;
  logic [WIDTH-1:0]       rdata;
  logic                   full;
  logic                   empty;
  logic [$clog2(DEPTH):0] count;
  logic                   overflow;
  logic                   underflow;

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output wr_en, rd_en, wdata;
    input  full, empty;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input wr_en, rd_en, wdata, rdata, full, empty, count, overflow, underflow;
  endclocking
endinterface
