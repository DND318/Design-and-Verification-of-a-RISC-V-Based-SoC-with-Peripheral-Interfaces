`timescale 1ns/1ps
// Single-port synchronous RAM, DEPTH x 32 bit with 4 byte-write enables.
// Built as four 8-bit lanes so every tool (Quartus, Vivado, Yosys) infers
// plain block RAM. Read data appears one cycle after en_i (read-first).
// INIT_FILE_B0..B3: optional $readmemh files, one per byte lane (lane 0 =
// bits 7:0), made by scripts/elf2hex.py; empty string = no init.
module sram_sp #(
  parameter DEPTH        = 4096,
  parameter AW           = 12,
  parameter INIT_FILE_B0 = "",
  parameter INIT_FILE_B1 = "",
  parameter INIT_FILE_B2 = "",
  parameter INIT_FILE_B3 = ""
) (
  input  wire          clk_i,
  input  wire          en_i,
  input  wire [3:0]    we_i,      // byte write enables, ignored when en_i = 0
  input  wire [AW-1:0] addr_i,    // word address
  input  wire [31:0]   wdata_i,
  output wire [31:0]   rdata_o
);

  reg [7:0] lane0 [0:DEPTH-1];
  reg [7:0] lane1 [0:DEPTH-1];
  reg [7:0] lane2 [0:DEPTH-1];
  reg [7:0] lane3 [0:DEPTH-1];
  reg [7:0] q0, q1, q2, q3;

  initial begin
    if (INIT_FILE_B0 != "") $readmemh(INIT_FILE_B0, lane0);
    if (INIT_FILE_B1 != "") $readmemh(INIT_FILE_B1, lane1);
    if (INIT_FILE_B2 != "") $readmemh(INIT_FILE_B2, lane2);
    if (INIT_FILE_B3 != "") $readmemh(INIT_FILE_B3, lane3);
  end

  always @(posedge clk_i) begin
    if (en_i) begin
      if (we_i[0]) lane0[addr_i] <= wdata_i[7:0];
      q0 <= lane0[addr_i];
    end
  end

  always @(posedge clk_i) begin
    if (en_i) begin
      if (we_i[1]) lane1[addr_i] <= wdata_i[15:8];
      q1 <= lane1[addr_i];
    end
  end

  always @(posedge clk_i) begin
    if (en_i) begin
      if (we_i[2]) lane2[addr_i] <= wdata_i[23:16];
      q2 <= lane2[addr_i];
    end
  end

  always @(posedge clk_i) begin
    if (en_i) begin
      if (we_i[3]) lane3[addr_i] <= wdata_i[31:24];
      q3 <= lane3[addr_i];
    end
  end

  assign rdata_o = {q3, q2, q1, q0};

endmodule
