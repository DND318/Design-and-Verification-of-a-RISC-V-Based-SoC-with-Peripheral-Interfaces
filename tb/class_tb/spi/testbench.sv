// SPI testbench top (make tests TOP=spi)
`timescale 1ns/1ps
module testbench;
  import apb_vip_pkg::*;
  import spi_pkg::*;
  import test_pkg::*;

  logic clk;
  apb_if apb_if_0 (clk);
  spi_if spi_if_0 (clk);

  wire [31:0] prdata;
  wire        pready, pslverr, irq_spi, sclk, mosi, cs_n;

  spi_apb u_dut (
    .clk_i      (clk),
    .rst_ni     (apb_if_0.rst_n),
    .psel_i     (apb_if_0.psel),
    .penable_i  (apb_if_0.penable),
    .pwrite_i   (apb_if_0.pwrite),
    .paddr_i    (apb_if_0.paddr),
    .pwdata_i   (apb_if_0.pwdata),
    .pstrb_i    (apb_if_0.pstrb),
    .prdata_o   (prdata),
    .pready_o   (pready),
    .pslverr_o  (pslverr),
    .spi_sclk_o (sclk),
    .spi_mosi_o (mosi),
    .spi_miso_i (spi_if_0.miso),
    .spi_cs_no  (cs_n),
    .irq_spi_o  (irq_spi)
  );

  // DUT outputs into the interfaces with an event-controlled block, not with
  // assign (Verilator 5.020: "Input combinational region did not converge").
  always @(prdata or pready or pslverr or irq_spi) begin
    apb_if_0.prdata  <= prdata;
    apb_if_0.pready  <= pready;
    apb_if_0.pslverr <= pslverr;
    apb_if_0.irq     <= {7'd0, irq_spi};
  end
  always @(sclk or mosi or cs_n or irq_spi or apb_if_0.rst_n) begin
    spi_if_0.sclk  <= sclk;
    spi_if_0.mosi  <= mosi;
    spi_if_0.cs_n  <= cs_n;
    spi_if_0.irq   <= irq_spi;
    spi_if_0.rst_n <= apb_if_0.rst_n;
  end

  // 50 MHz clock
  initial begin
    clk = 1'b0;
    forever begin
      #10ns;
      clk = ~clk;
    end
  end

  initial begin
    apb_if_0.rst_n = 1'b0;
    #100ns apb_if_0.rst_n = 1'b1;
  end

  initial begin
    #50ms;
    $display("[testbench] Time out....Seems your tb is hang!");
    $display("TEST FAILED");
    $finish;
  end

  spi_base_test   test;
  spi_reg_test    reg_test;
  spi_mode_test   mode_test;
  spi_timing_test timing_test;
  spi_fifo_test   fifo_test;
  spi_irq_test    irq_test;
  spi_rand_test   rand_test;

  initial begin
    if ($test$plusargs("spi_reg_test")) begin
      $display("%0t: [testbench] Run spi_reg_test", $time);
      reg_test = new();
      test = reg_test;
    end
    else if ($test$plusargs("spi_mode_test")) begin
      $display("%0t: [testbench] Run spi_mode_test", $time);
      mode_test = new();
      test = mode_test;
    end
    else if ($test$plusargs("spi_timing_test")) begin
      $display("%0t: [testbench] Run spi_timing_test", $time);
      timing_test = new();
      test = timing_test;
    end
    else if ($test$plusargs("spi_fifo_test")) begin
      $display("%0t: [testbench] Run spi_fifo_test", $time);
      fifo_test = new();
      test = fifo_test;
    end
    else if ($test$plusargs("spi_irq_test")) begin
      $display("%0t: [testbench] Run spi_irq_test", $time);
      irq_test = new();
      test = irq_test;
    end
    else if ($test$plusargs("spi_rand_test")) begin
      $display("%0t: [testbench] Run spi_rand_test", $time);
      rand_test = new();
      test = rand_test;
    end
    else begin
      $display("%0t: [testbench] Run spi_base_test", $time);
      test = new();
    end
    test.apb_vif = apb_if_0;
    test.spi_vif = spi_if_0;
    test.run_test();
  end
endmodule
