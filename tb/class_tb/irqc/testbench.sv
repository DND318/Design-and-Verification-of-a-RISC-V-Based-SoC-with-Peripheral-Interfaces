// IRQC testbench top (make tests TOP=irqc)
`timescale 1ns/1ps
module testbench;
  import apb_vip_pkg::*;
  import irqc_pkg::*;
  import test_pkg::*;

  logic clk;
  apb_if  apb_if_0 (clk);
  irqc_if irqc_if_0 (clk);

  wire [31:0] prdata;
  wire        pready, pslverr, irq_meip;

  irqc_apb u_dut (
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
    .irq_uart_i(irqc_if_0.irq_in[0]),
    .irq_spi_i (irqc_if_0.irq_in[1]),
    .irq_i2c_i (irqc_if_0.irq_in[2]),
    .irq_gpio_i(irqc_if_0.irq_in[3]),
    .irq_meip_o(irq_meip)
  );

  // DUT outputs into the interfaces with an event-controlled block, not with
  // assign (Verilator 5.020: "Input combinational region did not converge").
  always @(prdata or pready or pslverr or irq_meip) begin
    apb_if_0.prdata  <= prdata;
    apb_if_0.pready  <= pready;
    apb_if_0.pslverr <= pslverr;
    apb_if_0.irq     <= {7'd0, irq_meip};
  end
  always @(irq_meip or apb_if_0.rst_n) begin
    irqc_if_0.irq   <= irq_meip;
    irqc_if_0.rst_n <= apb_if_0.rst_n;
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

  irqc_base_test   test;
  irqc_reg_test    reg_test;
  irqc_func_test   func_test;
  irqc_prio_test   prio_test;
  irqc_reset_test  reset_test;
  irqc_rand_test   rand_test;

  initial begin
    if ($test$plusargs("irqc_reg_test")) begin
      $display("%0t: [testbench] Run irqc_reg_test", $time);
      reg_test = new();
      test = reg_test;
    end
    else if ($test$plusargs("irqc_func_test")) begin
      $display("%0t: [testbench] Run irqc_func_test", $time);
      func_test = new();
      test = func_test;
    end
    else if ($test$plusargs("irqc_prio_test")) begin
      $display("%0t: [testbench] Run irqc_prio_test", $time);
      prio_test = new();
      test = prio_test;
    end
    else if ($test$plusargs("irqc_reset_test")) begin
      $display("%0t: [testbench] Run irqc_reset_test", $time);
      reset_test = new();
      test = reset_test;
    end
    else if ($test$plusargs("irqc_rand_test")) begin
      $display("%0t: [testbench] Run irqc_rand_test", $time);
      rand_test = new();
      test = rand_test;
    end
    else begin
      $display("%0t: [testbench] Run irqc_base_test", $time);
      test = new();
    end
    test.apb_vif  = apb_if_0;
    test.irqc_vif = irqc_if_0;
    test.run_test();
  end
endmodule
