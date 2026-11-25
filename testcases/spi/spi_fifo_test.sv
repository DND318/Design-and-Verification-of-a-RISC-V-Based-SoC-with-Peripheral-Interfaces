// spi_fifo_test: SPI-30, 31, 33..35: enable, FIFOs, busy
class spi_fifo_test extends spi_base_test;
  function new();
    super.new();
    name = "spi_fifo_test";
  endfunction

  virtual task run_scenario();
    test_en_off();
    test_en_cleared();
    test_tx_overflow();
    test_rx_overrun();
    test_busy();
  endtask

  task test_en_off();
    $display("%0t: [%s] spi_en = 0: nothing is sent", $time, name);
    item("SPI-30");
    slave(8'hC1); slave(8'hC2); slave(8'hC3);
    setup_mode(0, 1, 0, 1);
    write(TXDATA, 32'h21);
    write(TXDATA, 32'h42);
    write(TXDATA, 32'h84);
    clks(200);
    check(frame_count() == 0 && sb.busy_n == 0, "spi_en = 0: no SCLK edge");
    rd_check(STATUS, S_RXEMPTY, "spi_en = 0: TX FIFO keeps its 3 bytes, not busy");
    rd_check(ISR, 32'h0, "spi_en = 0: no done");
    write(CTRL, mode_bits(0, 1, 0) | C_EN);
    wait_frames(3);
    clks(2);
    rd_check(RXDATA, 32'hC1, "spi_en = 1: byte 0");
    rd_check(RXDATA, 32'hC2, "spi_en = 1: byte 1");
    rd_check(RXDATA, 32'hC3, "spi_en = 1: byte 2");
    write(CTRL, 32'h0);
    write(CS, 32'h1);
  endtask

  task test_en_cleared();
    bit [31:0] m = mode_bits(1, 0, 0);
    $display("%0t: [%s] spi_en cleared in the middle of a burst", $time, name);
    item("SPI-31");
    for (int i = 0; i < 6; i++) slave(8'(8'hD0 + i));
    setup_mode(1, 0, 0, 7);
    for (int i = 0; i < 6; i++) write(TXDATA, 8'(8'h60 + i));
    write(CTRL, m | C_EN);
    wait_frames(1);                              // frame 2 has started
    write(CTRL, m);
    clks(3 * 16 * 8);
    check(frame_count() == 1 && sb.busy_n == 0,
          $sformatf("spi_en = 0 in a burst: the frame in progress ends, %0d more frames, expected 1", frame_count()));
    seen += frame_count();
    rd_check(STATUS, 32'h0, "4 bytes left in the TX FIFO, 2 received, not busy");
    rd_check(ISR, 32'h0, "no done: the TX FIFO is not empty");
    write(CTRL, m | C_EN);
    wait_frames(4);
    clks(2);
    rd_check(ISR, I_DONE, "done after the last byte");
    for (int i = 0; i < 6; i++) rd_check(RXDATA, 8'(8'hD0 + i), $sformatf("burst byte %0d", i));
    write(CTRL, 32'h0);
    write(CS, 32'h1);
  endtask

  task test_tx_overflow();
    $display("%0t: [%s] TX FIFO full", $time, name);
    item("SPI-33");
    setup_mode(0, 0, 0, 0);
    for (int i = 0; i < 16; i++) begin
      write(TXDATA, 8'(i * 17));
      if (i == 0)  rd_check(STATUS, S_RXEMPTY, "TX FIFO not empty after one write");
    end
    rd_check(STATUS, S_RXEMPTY | S_TXFULL, "TX FIFO full after 16 writes");
    write(TXDATA, 32'hEE);
    rd_check(STATUS, S_RXEMPTY | S_TXFULL, "17th write: still 16 bytes");
    rd_check(ISR, 32'h0, "17th write: no flag (none in the register map)");
    write(CTRL, C_EN);
    wait_frames(16);
    clks(16 * 2 + 20);
    check(frame_count() == 0 && sb.busy_n == 0, "the dropped byte is not sent");
    rd_check(STATUS, S_TXEMPTY | S_RXFULL, "16 frames, RX FIFO full");
    for (int i = 0; i < 16; i++) begin
      bit [31:0] d;
      read(RXDATA, d);                           // compared by the scoreboard
    end
    write(CTRL, 32'h0);
    write(CS, 32'h1);
  endtask

  task test_rx_overrun();
    bit [7:0] din[$];
    $display("%0t: [%s] RX FIFO full and overrun", $time, name);
    item("SPI-34");
    for (int i = 0; i < 18; i++) din.push_back(8'(8'h90 ^ (i * 5)));
    foreach (din[i]) slave(din[i]);
    setup_mode(0, 1, 1, 1);
    for (int i = 0; i < 16; i++) write(TXDATA, 8'(i));
    write(CTRL, mode_bits(0, 1, 1) | C_EN);
    wait_frames(16);
    clks(2);
    rd_check(STATUS, S_TXEMPTY | S_RXFULL, "RX FIFO full");
    rd_check(ISR, I_DONE, "no overrun yet");
    write(TXDATA, 32'hAB);
    write(TXDATA, 32'hCD);
    wait_frames(2);
    clks(2);
    rd_check(ISR, I_DONE | I_OVR, "rx_ovr set: frames ended with the RX FIFO full");
    rd_check(STATUS, S_TXEMPTY | S_RXFULL, "RX FIFO still full");
    apb_setup_only(RXDATA, 1'b0, 32'h0);
    for (int i = 0; i < 16; i++) rd_check(RXDATA, {24'd0, din[i]}, $sformatf("RX FIFO entry %0d", i));
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "RX FIFO empty: the 2 lost bytes were not stored, SETUP phase did not pop");
    rd_check(RXDATA, 32'h0, "lost bytes not in the FIFO");
    rd_check(ISR, I_DONE | I_OVR, "rx_ovr stays until cleared");
    write(ISR, I_OVR);
    rd_check(ISR, I_DONE, "rx_ovr cleared by W1C");
    write(CTRL, 32'h0);
    write(CS, 32'h1);
  endtask

  task test_busy();
    $display("%0t: [%s] STATUS.busy", $time, name);
    item("SPI-35");
    setup_mode(0, 0, 0, 12);
    rd_mask(STATUS, S_BUSY, 32'h0, "idle: busy = 0");
    write(TXDATA, 32'h5A);
    write(CTRL, C_EN);
    clks(4);
    rd_mask(STATUS, S_BUSY | S_TXEMPTY, S_BUSY | S_TXEMPTY, "busy right after the start (before the first edge)");
    clks(100);
    rd_mask(STATUS, S_BUSY | S_TXEMPTY, S_BUSY | S_TXEMPTY, "busy in the middle of the frame");
    wait_frames(1);
    rd_mask(STATUS, S_BUSY, 32'h0, "busy = 0 after the frame");
    write(TXDATA, 32'hA5);
    write(TXDATA, 32'h3C);
    clks(16 * 13 + 2);
    rd_mask(STATUS, S_BUSY, S_BUSY, "busy between back-to-back frames");
    wait_frames(2);
    rd_mask(STATUS, S_BUSY, 32'h0, "busy = 0 after the burst");
    write(CTRL, 32'h0);
    write(CS, 32'h1);
  endtask
endclass
