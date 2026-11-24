// Directed, self-checking testbench for sync_fifo.
// A queue model predicts every output; any mismatch is counted.
// Ends with "TEST PASSED" or "TEST FAILED" for scripts/check_log.sh.
`timescale 1ns/1ps
module tb_sync_fifo;

  localparam int unsigned WIDTH = 8;
  localparam int unsigned DEPTH = 16;

  logic                   clk = 1'b0;
  logic                   rst_n = 1'b0;
  logic                   wr_en = 1'b0;
  logic                   rd_en = 1'b0;
  logic [WIDTH-1:0]       wdata = '0;
  logic [WIDTH-1:0]       rdata;
  logic                   full, empty, overflow, underflow;
  logic [$clog2(DEPTH):0] count;

  logic [WIDTH-1:0] model [$];
  int unsigned      errors = 0;
  int unsigned      checks = 0;

  always #5 clk = ~clk;

  sync_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .wr_en_i(wr_en), .wdata_i(wdata), .rd_en_i(rd_en),
    .rdata_o(rdata), .full_o(full), .empty_o(empty), .count_o(count),
    .overflow_o(overflow), .underflow_o(underflow)
  );

  task automatic check(input logic ok, input string what);
    checks++;
    if (!ok) begin
      errors++;
      $display("[%0t] ERROR: %s", $time, what);
    end
  endtask

  // One clock cycle: drive after the falling edge, check outputs, then
  // update the model at the rising edge.
  task automatic cycle(input logic wr, input logic [WIDTH-1:0] d, input logic rd);
    bit do_wr, do_rd;
    @(negedge clk);
    wr_en = wr;
    wdata = d;
    rd_en = rd;
    #1;
    check(empty     === (model.size() == 0),     $sformatf("empty=%b size=%0d", empty, model.size()));
    check(full      === (model.size() == DEPTH), $sformatf("full=%b size=%0d", full, model.size()));
    check(count     === ($clog2(DEPTH)+1)'(model.size()), $sformatf("count=%0d size=%0d", count, model.size()));
    check(overflow  === (wr && model.size() == DEPTH), "overflow");
    check(underflow === (rd && model.size() == 0), "underflow");
    if (model.size() != 0)
      check(rdata === model[0], $sformatf("rdata=%h expected %h", rdata, model[0]));
    do_wr = wr && (model.size() < DEPTH);
    do_rd = rd && (model.size() > 0);
    @(posedge clk);
    if (do_rd) void'(model.pop_front());
    if (do_wr) model.push_back(d);
  endtask

  initial begin
    $display("tb_sync_fifo: WIDTH=%0d DEPTH=%0d", WIDTH, DEPTH);
    repeat (3) @(posedge clk);
    // T1: reset values
    #1;
    check(empty === 1'b1 && full === 1'b0 && count === '0, "reset values while in reset");
    rst_n = 1'b1;

    // T2: fill to full, then two extra writes (overflow)
    for (int i = 0; i < DEPTH + 2; i++) cycle(1'b1, WIDTH'(i * 7 + 1), 1'b0);

    // T3: drain to empty, then two extra reads (underflow)
    for (int i = 0; i < DEPTH + 2; i++) cycle(1'b0, '0, 1'b1);

    // T4: simultaneous read and write at mid level
    for (int i = 0; i < DEPTH / 2; i++) cycle(1'b1, WIDTH'(32'hA0 + i), 1'b0);
    for (int i = 0; i < 20; i++)        cycle(1'b1, WIDTH'(32'h50 + i), 1'b1);

    // T5: simultaneous read and write when full (write is blocked)
    while (model.size() < DEPTH) cycle(1'b1, 8'h33, 1'b0);
    cycle(1'b1, 8'hEE, 1'b1);

    // T6: random traffic
    for (int i = 0; i < 5000; i++) cycle(1'($urandom_range(0, 1)), WIDTH'($urandom), 1'($urandom_range(0, 1)));

    // T7: reset in the middle of traffic
    @(negedge clk);
    wr_en = 1'b0;
    rd_en = 1'b0;
    rst_n = 1'b0;
    model.delete();
    @(negedge clk);
    check(empty === 1'b1 && count === '0, "empty after mid-run reset");
    rst_n = 1'b1;
    for (int i = 0; i < 4; i++) cycle(1'b1, WIDTH'(i), 1'b0);
    for (int i = 0; i < 4; i++) cycle(1'b0, '0, 1'b1);

    $display("checks=%0d errors=%0d", checks, errors);
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED");
    $finish;
  end

  initial begin
    #2_000_000;
    $display("TEST FAILED: timeout");
    $finish;
  end

endmodule
