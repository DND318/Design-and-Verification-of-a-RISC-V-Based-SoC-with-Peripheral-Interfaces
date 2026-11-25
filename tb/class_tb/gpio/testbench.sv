// GPIO testbench top (make tests TOP=gpio)
`timescale 1ns/1ps
module testbench;
  import apb_vip_pkg::*;
  import gpio_pkg::*;
  import test_pkg::*;

  logic clk;
  apb_if  apb_if_0 (clk);
  gpio_if gpio_if_0 (clk);

  wire [31:0] prdata;
  wire        pready, pslverr, irq_gpio;
  wire [7:0]  gpio_o, gpio_oe;

  gpio_apb u_dut (
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
    .gpio_o    (gpio_o),
    .gpio_oe_o (gpio_oe),
    .gpio_i    (gpio_if_0.gpio_i),
    .irq_gpio_o(irq_gpio)
  );

  // DUT outputs into the interfaces with an event-controlled block, not with
  // assign (Verilator 5.020: "Input combinational region did not converge").
  always @(prdata or pready or pslverr or irq_gpio) begin
    apb_if_0.prdata  <= prdata;
    apb_if_0.pready  <= pready;
    apb_if_0.pslverr <= pslverr;
    apb_if_0.irq     <= {7'd0, irq_gpio};
  end
  always @(gpio_o or gpio_oe or irq_gpio or apb_if_0.rst_n) begin
    gpio_if_0.gpio_o  <= gpio_o;
    gpio_if_0.gpio_oe <= gpio_oe;
    gpio_if_0.irq     <= irq_gpio;
    gpio_if_0.rst_n   <= apb_if_0.rst_n;
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
    #20ms;
    $display("[testbench] Time out....Seems your tb is hang!");
    $display("TEST FAILED");
    $finish;
  end

  gpio_base_test   test;
  gpio_reg_test    reg_test;
  gpio_input_test  input_test;
  gpio_irq_test    irq_test;
  gpio_reset_test  reset_test;
  gpio_rand_test   rand_test;

  initial begin
    if ($test$plusargs("gpio_reg_test")) begin
      $display("%0t: [testbench] Run gpio_reg_test", $time);
      reg_test = new();
      test = reg_test;
    end
    else if ($test$plusargs("gpio_input_test")) begin
      $display("%0t: [testbench] Run gpio_input_test", $time);
      input_test = new();
      test = input_test;
    end
    else if ($test$plusargs("gpio_irq_test")) begin
      $display("%0t: [testbench] Run gpio_irq_test", $time);
      irq_test = new();
      test = irq_test;
    end
    else if ($test$plusargs("gpio_reset_test")) begin
      $display("%0t: [testbench] Run gpio_reset_test", $time);
      reset_test = new();
      test = reset_test;
    end
    else if ($test$plusargs("gpio_rand_test")) begin
      $display("%0t: [testbench] Run gpio_rand_test", $time);
      rand_test = new();
      test = rand_test;
    end
    else begin
      $display("%0t: [testbench] Run gpio_base_test", $time);
      test = new();
    end
    test.apb_vif  = apb_if_0;
    test.gpio_vif = gpio_if_0;
    test.run_test();
  end
endmodule
