// Timer testbench top (make tests TOP=timer)
`timescale 1ns/1ps
module testbench;
  import apb_vip_pkg::*;
  import timer_pkg::*;
  import test_pkg::*;

  logic clk;
  apb_if apb_if_0 (clk);

  wire [31:0] prdata;
  wire        pready, pslverr, irq_mtip;

  timer_apb u_dut (
    .clk_i     (clk),
    .rst_ni    (apb_if_0.rst_n),
    .psel_i    (apb_if_0.psel),
    .penable_i (apb_if_0.penable),
    .pwrite_i  (apb_if_0.pwrite),
    .paddr_i   (apb_if_0.paddr),
    .pwdata_i  (apb_if_0.pwdata),
    .pstrb_i   (apb_if_0.pstrb),
    .prdata_o  (prdata),
    .pready_o  (pready),
    .pslverr_o (pslverr),
    .irq_mtip_o(irq_mtip)
  );

  // DUT outputs into the interface with an event-controlled block, not with
  // assign (Verilator 5.020: "Input combinational region did not converge").
  always @(prdata or pready or pslverr or irq_mtip) begin
    apb_if_0.prdata  <= prdata;
    apb_if_0.pready  <= pready;
    apb_if_0.pslverr <= pslverr;
    apb_if_0.irq     <= {7'd0, irq_mtip};
  end

  // 100 MHz clock
  initial begin
    clk = 1'b0;
    forever begin
      #5ns;
      clk = ~clk;
    end
  end

  initial begin
    apb_if_0.rst_n = 1'b0;
    #31ns apb_if_0.rst_n = 1'b1;
  end

  initial begin
    #20ms;
    $display("[testbench] Time out....Seems your tb is hang!");
    $display("TEST FAILED");
    $finish;
  end

  timer_base_test  test;
  timer_reg_test   reg_test;
  timer_div_test   div_test;
  timer_count_test count_test;
  timer_cmp_test   cmp_test;
  timer_reset_test reset_test;
  timer_rand_test  rand_test;

  initial begin
    if ($test$plusargs("timer_reg_test")) begin
      $display("%0t: [testbench] Run timer_reg_test", $time);
      reg_test = new();
      test = reg_test;
    end
    else if ($test$plusargs("timer_div_test")) begin
      $display("%0t: [testbench] Run timer_div_test", $time);
      div_test = new();
      test = div_test;
    end
    else if ($test$plusargs("timer_count_test")) begin
      $display("%0t: [testbench] Run timer_count_test", $time);
      count_test = new();
      test = count_test;
    end
    else if ($test$plusargs("timer_cmp_test")) begin
      $display("%0t: [testbench] Run timer_cmp_test", $time);
      cmp_test = new();
      test = cmp_test;
    end
    else if ($test$plusargs("timer_reset_test")) begin
      $display("%0t: [testbench] Run timer_reset_test", $time);
      reset_test = new();
      test = reset_test;
    end
    else if ($test$plusargs("timer_rand_test")) begin
      $display("%0t: [testbench] Run timer_rand_test", $time);
      rand_test = new();
      test = rand_test;
    end
    else begin
      $display("%0t: [testbench] Run timer_base_test", $time);
      test = new();
    end
    test.apb_vif = apb_if_0;
    test.run_test();
  end
endmodule
