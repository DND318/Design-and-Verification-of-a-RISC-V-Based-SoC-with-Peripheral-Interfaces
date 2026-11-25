// spi_reg_test: SPI-01..23: registers
class spi_reg_test extends spi_base_test;
  function new();
    super.new();
    name = "spi_reg_test";
  endfunction

  virtual task during_reset();
    clks(3);
    #1;
    item("SPI-05");
    check(spi_vif.cs_n === 1'b1 && spi_vif.sclk === 1'b0 && apb_vif.irq[0] === 1'b0,
          $sformatf("outputs during reset: spi_cs_no = %b, spi_sclk_o = %b, irq_spi_o = %b",
                    spi_vif.cs_n, spi_vif.sclk, apb_vif.irq[0]));
  endtask

  virtual task run_scenario();
    vp_regs();                                   // generated register items SPI-01..21
    test_reset_values();
    test_side_effects();
  endtask

  task test_reset_values();
    $display("%0t: [%s] reset values, reserved offsets", $time, name);
    item("SPI-01");
    rd_check(CTRL,   32'h0000_0000, "CTRL reset");
    rd_check(CLKDIV, 32'h0000_0001, "CLKDIV reset");
    rd_check(CS,     32'h0000_0001, "CS reset");
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "STATUS reset");
    rd_check(TXDATA, 32'h0, "TXDATA reset");
    rd_check(RXDATA, 32'h0, "RXDATA reset");
    rd_check(IER,    32'h0, "IER reset");
    rd_check(ISR,    32'h0, "ISR reset");
    item("SPI-06");
    write(CS, 32'h0);
    #1;
    check(spi_vif.cs_n === 1'b0, "CS = 0 drives spi_cs_no low");
    write(CS, 32'h0000_0001, 4'b1110);
    #1;
    check(spi_vif.cs_n === 1'b0, "CS write with PSTRB[0] = 0 ignored");
    write(CS, 32'h1);
    #1;
    check(spi_vif.cs_n === 1'b1, "CS = 1 drives spi_cs_no high");
    item("SPI-02");
    write(CTRL, mode_bits(1, 0, 0));
    clks(3);
    check(spi_vif.sclk === 1'b1, "CPOL = 1: SCLK idles high");
    write(CTRL, 32'h0);
    clks(3);
    check(spi_vif.sclk === 1'b0, "CPOL = 0: SCLK idles low");
    item("SPI-16");
    write(12'h020, 32'hFFFF_FFFF);
    write(12'hFFC, 32'hFFFF_FFFF);
    rd_check(CTRL, 32'h0,   "reserved writes leave CTRL");
    rd_check(CLKDIV, 32'h1, "reserved writes leave CLKDIV");
    rd_check(CS, 32'h1,     "reserved writes leave CS");
    rd_check(IER, 32'h0,    "reserved writes leave IER");
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "reserved writes leave STATUS");
  endtask

  task test_side_effects();
    bit [31:0] d;
    $display("%0t: [%s] side effects: PSTRB[0] = 0, SETUP without ACCESS, read when empty", $time, name);
    item("SPI-22");
    write(TXDATA, 32'h55, 4'b1110);
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "TXDATA write with PSTRB[0] = 0 does not push");
    apb_setup_only(TXDATA, 1'b1, 32'h77);
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "TXDATA in SETUP only does not push");
    write(CTRL, C_EN);
    clks(80);
    check(sb.n_frames == 0 && sb.busy_n == 0, "no frame: nothing was pushed");
    write(TXDATA, 32'hFFFF_FF3C, 4'b0001);         // upper bytes ignored
    wait_frames(1);
    clks(2);
    rd_check(STATUS, S_TXEMPTY, "TXDATA with PSTRB[0] = 1 pushed one byte");
    rd_check(ISR, I_DONE, "done after the frame");
    write(CTRL, 32'h0);
    item("SPI-23");
    read(RXDATA, d);                              // pop the received byte (compared by the scoreboard)
    rd_check(RXDATA, 32'h0, "RXDATA read when empty returns 0");
    rd_check(RXDATA, 32'h0, "RXDATA read when empty returns 0 (again)");
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "read when empty: FIFO still empty");
    write(ISR, I_DONE);
    rd_check(ISR, 32'h0, "read when empty sets no flag");
  endtask
endclass
