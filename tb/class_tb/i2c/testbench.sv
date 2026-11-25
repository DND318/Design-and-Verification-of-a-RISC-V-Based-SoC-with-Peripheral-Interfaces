// I2C testbench top (make tests TOP=i2c)
`timescale 1ns/1ps
module testbench;
  import apb_vip_pkg::*;
  import i2c_pkg::*;
  import test_pkg::*;

  logic clk;
  apb_if apb_if_0 (clk);
  i2c_if i2c_if_0 (clk);

  wire [31:0] prdata;
  wire        pready, pslverr, irq_i2c;
  wire        scl_o, scl_oe, sda_o, sda_oe;

  // Wired-AND bus with pull-ups
  wire scl_bus = (scl_oe || i2c_if_0.ext_scl_low) ? 1'b0 : 1'b1;
  wire sda_bus = (sda_oe || i2c_if_0.sda_low || i2c_if_0.ext_sda_low) ? 1'b0 : 1'b1;

  i2c_apb u_dut (
    .clk_i        (clk),
    .rst_ni       (apb_if_0.rst_n),
    .psel_i       (apb_if_0.psel),
    .penable_i    (apb_if_0.penable),
    .pwrite_i     (apb_if_0.pwrite),
    .paddr_i      (apb_if_0.paddr),
    .pwdata_i     (apb_if_0.pwdata),
    .pstrb_i      (apb_if_0.pstrb),
    .prdata_o     (prdata),
    .pready_o     (pready),
    .pslverr_o    (pslverr),
    .i2c_scl_o    (scl_o),
    .i2c_scl_oe_o (scl_oe),
    .i2c_scl_i    (scl_bus),
    .i2c_sda_o    (sda_o),
    .i2c_sda_oe_o (sda_oe),
    .i2c_sda_i    (sda_bus),
    .irq_i2c_o    (irq_i2c)
  );

  // DUT outputs and bus lines into the interfaces with an event-controlled
  // block, not with assign (Verilator 5.020: "Input combinational region did
  // not converge").
  always @(prdata or pready or pslverr or irq_i2c) begin
    apb_if_0.prdata  <= prdata;
    apb_if_0.pready  <= pready;
    apb_if_0.pslverr <= pslverr;
    apb_if_0.irq     <= {7'd0, irq_i2c};
  end
  always @(scl_bus or sda_bus or scl_oe or sda_oe or scl_o or sda_o or irq_i2c or apb_if_0.rst_n) begin
    i2c_if_0.scl    <= scl_bus;
    i2c_if_0.sda    <= sda_bus;
    i2c_if_0.scl_oe <= scl_oe;
    i2c_if_0.sda_oe <= sda_oe;
    i2c_if_0.scl_o  <= scl_o;
    i2c_if_0.sda_o  <= sda_o;
    i2c_if_0.irq    <= irq_i2c;
    i2c_if_0.rst_n  <= apb_if_0.rst_n;
  end

  // 50 MHz clock (PRESCALE reset value 124 = 100 kHz SCL)
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
    #200ms;
    $display("[testbench] Time out....Seems your tb is hang!");
    $display("TEST FAILED");
    $finish;
  end

  i2c_base_test  test;
  i2c_reg_test   reg_test;
  i2c_write_test write_test;
  i2c_read_test  read_test;
  i2c_bus_test   bus_test;
  i2c_irq_test   irq_test;
  i2c_rand_test  rand_test;

  initial begin
    if ($test$plusargs("i2c_reg_test")) begin
      $display("%0t: [testbench] Run i2c_reg_test", $time);
      reg_test = new();
      test = reg_test;
    end
    else if ($test$plusargs("i2c_write_test")) begin
      $display("%0t: [testbench] Run i2c_write_test", $time);
      write_test = new();
      test = write_test;
    end
    else if ($test$plusargs("i2c_read_test")) begin
      $display("%0t: [testbench] Run i2c_read_test", $time);
      read_test = new();
      test = read_test;
    end
    else if ($test$plusargs("i2c_bus_test")) begin
      $display("%0t: [testbench] Run i2c_bus_test", $time);
      bus_test = new();
      test = bus_test;
    end
    else if ($test$plusargs("i2c_irq_test")) begin
      $display("%0t: [testbench] Run i2c_irq_test", $time);
      irq_test = new();
      test = irq_test;
    end
    else if ($test$plusargs("i2c_rand_test")) begin
      $display("%0t: [testbench] Run i2c_rand_test", $time);
      rand_test = new();
      test = rand_test;
    end
    else begin
      $display("%0t: [testbench] Run i2c_base_test", $time);
      test = new();
    end
    test.apb_vif = apb_if_0;
    test.i2c_vif = i2c_if_0;
    test.run_test();
  end
endmodule
