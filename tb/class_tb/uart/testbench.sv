// UART testbench top 
`timescale 1ns/1ps
module testbench;
  import apb_vip_pkg::*;
  import uart_pkg::*;
  import test_pkg::*;

  logic clk;
  apb_if  apb_if_0 (clk);
  uart_if uart_if_0 (clk);

  wire [31:0] prdata;
  wire        pready, pslverr, irq_uart, uart_tx;

  uart_apb u_dut (
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
    .uart_tx_o (uart_tx),
    .uart_rx_i (uart_if_0.rx),
    .irq_uart_o(irq_uart)
  );

  always @(prdata or pready or pslverr or irq_uart) begin
    apb_if_0.prdata  <= prdata;
    apb_if_0.pready  <= pready;
    apb_if_0.pslverr <= pslverr;
    apb_if_0.irq     <= {7'd0, irq_uart};
  end
  always @(uart_tx or u_dut.tx_ser) begin
    uart_if_0.tx     <= uart_tx;
    uart_if_0.tx_ser <= u_dut.tx_ser;
  end

  // 50 MHz clock (BAUD reset value 433 = 115200 baud)
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

  uart_base_test     test;
  uart_reg_test      reg_test;
  uart_tx_test       tx_test;
  uart_rx_test       rx_test;
  uart_loopback_test loopback_test;
  uart_irq_test      irq_test;
  uart_rand_test     rand_test;

  initial begin
    if ($test$plusargs("uart_reg_test")) begin
      $display("%0t: [testbench] Run uart_reg_test", $time);
      reg_test = new();
      test = reg_test;
    end
    else if ($test$plusargs("uart_tx_test")) begin
      $display("%0t: [testbench] Run uart_tx_test", $time);
      tx_test = new();
      test = tx_test;
    end
    else if ($test$plusargs("uart_rx_test")) begin
      $display("%0t: [testbench] Run uart_rx_test", $time);
      rx_test = new();
      test = rx_test;
    end
    else if ($test$plusargs("uart_loopback_test")) begin
      $display("%0t: [testbench] Run uart_loopback_test", $time);
      loopback_test = new();
      test = loopback_test;
    end
    else if ($test$plusargs("uart_irq_test")) begin
      $display("%0t: [testbench] Run uart_irq_test", $time);
      irq_test = new();
      test = irq_test;
    end
    else if ($test$plusargs("uart_rand_test")) begin
      $display("%0t: [testbench] Run uart_rand_test", $time);
      rand_test = new();
      test = rand_test;
    end
    else begin
      $display("%0t: [testbench] Run uart_base_test", $time);
      test = new();
    end
    test.apb_vif  = apb_if_0;
    test.uart_vif = uart_if_0;
    test.run_test();
  end
endmodule
