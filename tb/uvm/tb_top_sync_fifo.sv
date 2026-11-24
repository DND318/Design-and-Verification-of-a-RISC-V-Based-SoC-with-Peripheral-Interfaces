`timescale 1ns/1ps
module tb_top_sync_fifo;
  import uvm_pkg::*;
  import fifo_vip_pkg::*;
  import test_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  always #5 clk = ~clk;

  initial begin
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
  end

  fifo_if vif (.clk(clk), .rst_n(rst_n));

  sync_fifo #(.WIDTH(fifo_vip_pkg::WIDTH), .DEPTH(fifo_vip_pkg::DEPTH)) dut (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .wr_en_i    (vif.wr_en),
    .wdata_i    (vif.wdata),
    .rd_en_i    (vif.rd_en),
    .rdata_o    (vif.rdata),
    .full_o     (vif.full),
    .empty_o    (vif.empty),
    .count_o    (vif.count),
    .overflow_o (vif.overflow),
    .underflow_o(vif.underflow)
  );

  initial begin
    uvm_config_db#(virtual fifo_if)::set(null, "*", "vif", vif);
    run_test();
  end
endmodule
