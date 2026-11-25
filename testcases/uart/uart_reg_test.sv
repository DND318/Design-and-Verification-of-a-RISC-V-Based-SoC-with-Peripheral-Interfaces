// uart_reg_test: UART-01..22: registers
class uart_reg_test extends uart_base_test;
  function new();
    super.new();
    name = "uart_reg_test";
  endfunction

  virtual task during_reset();
    clks(3);
    #1;
    item("UART-01");
    check(uart_vif.tx === 1'b1 && apb_vif.irq[0] === 1'b0,
          $sformatf("outputs during reset: uart_tx_o = %b, irq_uart_o = %b", uart_vif.tx, apb_vif.irq[0]));
  endtask

  virtual task run_scenario();
    vp_regs();                                   // generated register items UART-01..19
    test_reset_values();
    test_fields();
    test_side_effects();
  endtask

  task test_reset_values();
    $display("%0t: [%s] reset values, reserved offsets", $time, name);
    item("UART-01");
    rd_check(CTRL,   32'h0000_0000, "CTRL reset");
    rd_check(BAUD,   32'd433,       "BAUD reset");
    rd_check(STATUS, 32'h0000_000A, "STATUS reset");
    rd_check(TXDATA, 32'h0000_0000, "TXDATA reset");
    rd_check(RXDATA, 32'h0000_0000, "RXDATA reset");
    rd_check(IER,    32'h0000_0000, "IER reset");
    rd_check(ISR,    32'h0000_0001, "ISR reset");
    item("UART-14");
    rd_check(12'h01C, 32'h0, "reserved 0x1C");
    rd_check(12'h100, 32'h0, "reserved 0x100");
    rd_check(12'hFFC, 32'h0, "reserved 0xFFC");
  endtask

  task test_fields();
    $display("%0t: [%s] register fields, strobes, prohibited parity", $time, name);
    item("UART-02");
    write(CTRL, 32'hFFFF_FFF3);                     // all bits except parity
    rd_check(CTRL, 32'h33, "CTRL reserved bits read 0");
    write(CTRL, 32'h00);
    write(CTRL, 32'h04);  rd_check(CTRL, 32'h04, "CTRL parity even");
    write(CTRL, 32'h08);  rd_check(CTRL, 32'h08, "CTRL parity odd");
    write(CTRL, 32'h3C);  rd_check(CTRL, 32'h38, "CTRL parity = 11 keeps odd, other bits written");
    write(CTRL, 32'h04);
    write(CTRL, 32'h0C);  rd_check(CTRL, 32'h04, "CTRL parity = 11 keeps even, other bits cleared");
    write(CTRL, 32'h00);
    write(CTRL, 32'h0C);  rd_check(CTRL, 32'h00, "CTRL parity = 11 keeps none");
    write(CTRL, 32'h0000_0030, 4'b1110);
    rd_check(CTRL, 32'h00, "CTRL write with PSTRB[0] = 0 ignored");
    write(CTRL, 32'h0000_0030, 4'b0001);
    rd_check(CTRL, 32'h30, "CTRL write with PSTRB[0] = 1");
    write(CTRL, 32'h00);
    item("UART-04");
    write(BAUD, 32'h1234_ABCD, 4'b0001);
    rd_check(BAUD, 32'h0000_01CD, "BAUD byte 0 only");
    write(BAUD, 32'h1234_56EF, 4'b0010);
    rd_check(BAUD, 32'h0000_56CD, "BAUD byte 1 only");
    write(BAUD, 32'hFFFF_0000, 4'b1100);
    rd_check(BAUD, 32'h0000_56CD, "BAUD upper strobes ignored");
    write(BAUD, 32'hFFFF_FFFF);
    rd_check(BAUD, 32'h0000_FFFF, "BAUD reserved bits read 0");
    write(BAUD, 32'd433);
    rd_check(BAUD | 12'h1, 32'd433, "BAUD at PADDR[1:0] = 01 (byte address bits ignored)");
    item("UART-12");
    write(IER, 32'hFFFF_FFFF);
    rd_check(IER, 32'h3F, "IER all bits");
    write(IER, 32'h0, 4'b1110);
    rd_check(IER, 32'h3F, "IER PSTRB[0] = 0 ignored");
    write(IER, 32'h0);
    rd_check(IER, 32'h0, "IER cleared");
    item("UART-06");
    write(STATUS, 32'hFFFF_FFFF);
    rd_check(STATUS, 32'h0A, "STATUS is read-only");
    item("UART-44");
    write(ISR, 32'hFFFF_FFFF);
    rd_check(ISR, 32'h01, "ISR level bits are read-only");
    item("UART-10");
    write(RXDATA, 32'hFF);
    rd_check(STATUS, 32'h0A, "RXDATA write ignored");
    item("UART-14");
    write(12'h01C, 32'hFFFF_FFFF);
    write(12'h800, 32'hFFFF_FFFF);
    rd_check(CTRL, 32'h0,    "reserved writes leave CTRL");
    rd_check(BAUD, 32'd433,  "reserved writes leave BAUD");
    rd_check(IER,  32'h0,    "reserved writes leave IER");
    rd_check(STATUS, 32'h0A, "reserved writes leave STATUS");
  endtask

  task test_side_effects();
    $display("%0t: [%s] side effects: PSTRB[0] = 0, SETUP without ACCESS, read when empty", $time, name);
    item("UART-20");
    write(TXDATA, 32'h55, 4'b1110);
    rd_check(STATUS, 32'h0A, "TXDATA write with PSTRB[0] = 0 does not push");
    apb_setup_only(TXDATA, 1'b1, 32'h77);
    rd_check(STATUS, 32'h0A, "TXDATA in SETUP only does not push");
    item("UART-22");
    rd_check(RXDATA, 32'h0, "RXDATA read when empty returns 0");
    rd_check(RXDATA, 32'h0, "RXDATA read when empty returns 0 (again)");
    rd_check(ISR, I_TXEMPTY, "read when empty sets no flag");
    item("UART-21");
    write(BAUD, 32'd3);
    write(CTRL, C_RXEN);
    send_ok(8'h6E, 3, 2'b00, 1'b0);
    rx_wait();
    apb_setup_only(RXDATA, 1'b0, 32'h0);
    rd_check(RXDATA, 32'h6E, "RXDATA not popped by a SETUP phase");
    rd_mask(STATUS, S_RXEMPTY, S_RXEMPTY, "RX FIFO empty after one pop");
    write(CTRL, 32'h0);
    write(BAUD, 32'd433);
  endtask
endclass
