// i2c_reg_test: I2C-01..21, 34..36: registers and reset
class i2c_reg_test extends i2c_base_test;
  function new();
    super.new();
    name = "i2c_reg_test";
  endfunction

  virtual task run_scenario();
    vp_regs();                                   // generated register items I2C-01..21
    test_reset_values();
    test_fields();
    test_ignored();
  endtask

  task test_reset_values();
    $display("%0t: [%s] reset values, idle lines", $time, name);
    item("I2C-01");
    rd_check(CTRL,     32'h0,   "CTRL reset");
    rd_check(PRESCALE, 32'd124, "PRESCALE reset (100 kHz at 50 MHz)");
    rd_check(CMD,      32'h0,   "CMD reset");
    rd_check(TXDATA,   32'h0,   "TXDATA reset");
    rd_check(RXDATA,   32'h0,   "RXDATA reset");
    rd_check(STATUS,   32'h0,   "STATUS reset");
    rd_check(IER,      32'h0,   "IER reset");
    rd_check(ISR,      32'h0,   "ISR reset");
    item("I2C-36");
    check(i2c_vif.scl_oe === 1'b0 && i2c_vif.sda_oe === 1'b0 && i2c_vif.scl === 1'b1 && i2c_vif.sda === 1'b1,
          "after reset: both lines released, bus idle");
    check(i2c_vif.scl_o === 1'b0 && i2c_vif.sda_o === 1'b0, "open drain: scl_o = sda_o = 0");
    irq_is(1'b0, "after reset");
    item("I2C-16");
    rd_check(12'h020, 32'h0, "reserved 0x020");
    rd_check(12'hFFC, 32'h0, "reserved 0xFFC");
  endtask

  task test_fields();
    $display("%0t: [%s] register fields and strobes", $time, name);
    item("I2C-02");
    write(CTRL, 32'hFFFF_FFFE);    rd_check(CTRL, 32'h0, "CTRL write 0");
    write(CTRL, 32'hFFFF_FFFF, 4'hE); rd_check(CTRL, 32'h0, "CTRL PSTRB[0] = 0 ignored");
    write(CTRL, 32'hFFFF_FFFF);    rd_check(CTRL, 32'h1, "CTRL reserved bits read 0");
    write(CTRL, 32'h0);
    item("I2C-04");
    write(PRESCALE, 32'h0000_1234, 4'h1); rd_check(PRESCALE, 32'h0000_0034, "PRESCALE byte 0 only");
    write(PRESCALE, 32'h0000_5678, 4'h2); rd_check(PRESCALE, 32'h0000_5634, "PRESCALE byte 1 only");
    write(PRESCALE, 32'hFFFF_0000, 4'hC); rd_check(PRESCALE, 32'h0000_5634, "PRESCALE upper strobes ignored");
    write(PRESCALE, 32'd124);
    item("I2C-08");
    write(TXDATA, 32'hFFFF_FFA5);         rd_check(TXDATA, 32'hA5, "TXDATA reserved bits read 0");
    write(TXDATA, 32'h5A, 4'hE);          rd_check(TXDATA, 32'hA5, "TXDATA PSTRB[0] = 0 ignored");
    item("I2C-14");
    write(IER, 32'hFFFF_FFFF);            rd_check(IER, 32'h3, "IER all bits");
    write(IER, 32'h0, 4'hE);              rd_check(IER, 32'h3, "IER PSTRB[0] = 0 ignored");
    write(IER, 32'h0);                    rd_check(IER, 32'h0, "IER cleared");
    item("I2C-10");
    write(RXDATA, 32'hFFFF_FFFF);         rd_check(RXDATA, 32'h0, "RXDATA is read-only");
    item("I2C-12");
    write(STATUS, 32'hFFFF_FFFF);         rd_check(STATUS, 32'h0, "STATUS is read-only");
    item("I2C-15");
    write(ISR, 32'hFFFF_FFFF);            rd_check(ISR, 32'h0, "ISR W1C when clear: stays 0");
    item("I2C-16");
    write(12'h020, 32'hFFFF_FFFF);
    write(12'h800, 32'hFFFF_FFFF);
    rd_check(CTRL, 32'h0,       "reserved writes leave CTRL");
    rd_check(PRESCALE, 32'd124, "reserved writes leave PRESCALE");
    rd_check(TXDATA, 32'hA5,    "reserved writes leave TXDATA");
    rd_check(IER, 32'h0,        "reserved writes leave IER");
  endtask

  task test_ignored();
    int unsigned n0;
    $display("%0t: [%s] commands that must be ignored", $time, name);
    item("I2C-34");
    write(TXDATA, EE_W);
    write(CMD, C_START | C_WRITE);
    rd_check(STATUS, 32'h0, "i2c_en = 0: CMD ignored, not busy");
    clks(400);
    check(sb.n_start == 0 && sb.n_bytes == 0, "i2c_en = 0: nothing on the bus");
    check(i2c_vif.scl_oe === 1'b0 && i2c_vif.sda_oe === 1'b0, "i2c_en = 0: lines released");
    rd_check(ISR, 32'h0, "i2c_en = 0: no done");
    item("I2C-35");
    enable(4);
    n0 = sb.n_ignored;
    write(CMD, C_START | C_WRITE, 4'hE);
    rd_check(STATUS, 32'h0, "CMD with PSTRB[0] = 0 ignored");
    write(CMD, C_START | C_WRITE | C_READ);
    rd_check(STATUS, 32'h0, "CMD with read and write ignored");
    write(CMD, C_NACK);
    rd_check(STATUS, 32'h0, "CMD with no action bit ignored");
    write(CMD, 32'hE0);
    rd_check(STATUS, 32'h0, "CMD with reserved bits only ignored");
    clks(200);
    check(sb.n_start == 0 && sb.n_bytes == 0 && sb.n_stop == 0, "ignored commands: nothing on the bus");
    rd_check(ISR, 32'h0, "ignored commands: no done");
    check(sb.n_ignored - n0 == 3, $sformatf("scoreboard: %0d commands ignored, expected 3 (PSTRB[0] = 0 is not a CMD write)",
                                            sb.n_ignored - n0));
    write(CTRL, 32'h0);
  endtask
endclass
