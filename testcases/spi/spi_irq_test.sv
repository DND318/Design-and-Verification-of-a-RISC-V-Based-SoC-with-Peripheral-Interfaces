// spi_irq_test: SPI-36..38: interrupts
class spi_irq_test extends spi_base_test;
  function new();
    super.new();
    name = "spi_irq_test";
  endfunction

  virtual task run_scenario();
    test_done();
    test_gating();
    test_w1c();
  endtask

  task test_done();
    bit [31:0] m = mode_bits(0, 1, 0);
    $display("%0t: [%s] ISR.done, single frame and burst", $time, name);
    item("SPI-36");
    setup_mode(0, 1, 0, 4);
    write(IER, I_DONE);
    write(TXDATA, 32'h81);
    write(CTRL, m | C_EN);
    clks(20);
    rd_check(ISR, 32'h0, "single frame: no done during the frame");
    irq_check(1'b0, "single frame: no irq during the frame");
    wait_frames(1);
    rd_check(ISR, I_DONE, "single frame: done at the end");
    irq_check(1'b1, "single frame: irq with done_ie = 1");
    write(ISR, I_DONE);
    irq_check(1'b0, "done cleared: irq low");
    // burst of 4 bytes, written while spi_en = 0
    write(CTRL, m);
    for (int i = 0; i < 4; i++) write(TXDATA, 8'(8'h40 + i));
    write(CTRL, m | C_EN);
    for (int i = 0; i < 3; i++) begin
      wait_frames(1);
      rd_check(ISR, 32'h0, $sformatf("burst: no done after byte %0d (TX FIFO not empty)", i));
      irq_check(1'b0, $sformatf("burst: no irq after byte %0d", i));
    end
    wait_frames(1);
    rd_check(ISR, I_DONE, "burst: done after the last byte");
    irq_check(1'b1, "burst: irq after the last byte");
    // TX FIFO refilled during the burst: done only at the real end
    write(ISR, I_DONE);
    write(TXDATA, 32'h01);
    write(TXDATA, 32'h02);
    wait_frames(1);
    write(TXDATA, 32'h03);
    wait_frames(1);
    rd_check(ISR, 32'h0, "refilled burst: no done after byte 1");
    wait_frames(1);
    rd_check(ISR, I_DONE, "refilled burst: done after byte 2");
    write(CTRL, 32'h0);
    write(IER, 32'h0);
    write(ISR, I_DONE | I_OVR);
    for (int i = 0; i < 7; i++) begin
      bit [31:0] d;
      read(RXDATA, d);
    end
    write(CS, 32'h1);
  endtask

  // Make ISR = v (done from one frame, rx_ovr from a frame into a full RX FIFO)
  task set_isr(input bit [1:0] v);
    bit [31:0] d;
    write(ISR, I_DONE | I_OVR);
    if (v[1]) begin
      setup_mode(0, 0, 0, 0);
      for (int i = 0; i < 16; i++) write(TXDATA, 8'(i));
      write(CTRL, C_EN);
      wait_frames(16);
      write(TXDATA, 32'hFF);
      wait_frames(1);
      write(CTRL, 32'h0);
      repeat (16) read(RXDATA, d);
    end else if (v[0]) begin
      setup_mode(0, 0, 0, 0);
      write(TXDATA, 32'h99);
      write(CTRL, C_EN);
      wait_frames(1);
      write(CTRL, 32'h0);
      read(RXDATA, d);
    end
    if (!v[0]) write(ISR, I_DONE);
    clks(1);
    rd_check(ISR, {30'd0, v}, $sformatf("ISR set to %b", v));
  endtask

  task test_gating();
    $display("%0t: [%s] IER x ISR gating", $time, name);
    item("SPI-37");
    for (int s = 0; s < 4; s++) begin
      set_isr(2'(s));
      for (int e = 0; e < 4; e++) begin
        write(IER, e);
        irq_check(|(s & e), $sformatf("ISR %b, IER %b", 2'(s), 2'(e)));
      end
      write(IER, 32'h0);
    end
    write(ISR, I_DONE | I_OVR);
    write(CS, 32'h1);
  endtask

  task test_w1c();
    bit [31:0] d;
    int        n0, n1;
    $display("%0t: [%s] ISR W1C", $time, name);
    item("SPI-38");
    set_isr(2'b11);
    write(ISR, 32'h3, 4'b1110);
    rd_check(ISR, 32'h3, "PSTRB[0] = 0: no clear");
    write(ISR, 32'h0);
    rd_check(ISR, 32'h3, "writing 0: no clear");
    write(ISR, I_OVR);
    rd_check(ISR, I_DONE, "writing 1 to rx_ovr clears only rx_ovr");
    write(ISR, I_DONE);
    rd_check(ISR, 32'h0, "writing 1 to done clears it");
    write(IER, 32'h3);
    // W1C of done around the clock in which a frame ends (sets done)
    setup_mode(0, 1, 0, 0);
    for (int w = 12; w < 26; w++) begin
      write(ISR, I_DONE);
      write(TXDATA, 8'(w));
      write(CTRL, mode_bits(0, 1, 0) | C_EN);
      clks(w);
      write(ISR, I_DONE);                        // set-vs-clear: compared by the scoreboard
      wait_idle();
      read(ISR, d);
      if (d[0]) n1++; else n0++;
      write(CTRL, mode_bits(0, 1, 0));
      read(RXDATA, d);
    end
    $display("%0t: [%s] W1C sweep: done kept %0d times, cleared %0d times", $time, name, n1, n0);
    check(n0 > 0 && n1 > 0, "W1C sweep reached both sides of the frame end");
    write(IER, 32'h0);
    write(ISR, 32'h3);
    write(CS, 32'h1);
  endtask
endclass
