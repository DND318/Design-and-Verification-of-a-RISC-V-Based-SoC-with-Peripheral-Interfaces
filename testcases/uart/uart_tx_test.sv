// uart_tx_test: UART-23..30: transmitter
class uart_tx_test extends uart_base_test;
  function new();
    super.new();
    name = "uart_tx_test";
  endfunction

  virtual task run_scenario();
    test_formats();
    test_busy();
    test_default_baud();
    test_fifo();
    test_tx_en();
  endtask

  // Program one line setting, send n bytes back to back
  task tx_case(input int unsigned dv, input bit [1:0] p, input bit s2, input int unsigned n);
    bit [7:0] b;
    write(BAUD, dv);
    write(CTRL, C_TXEN | ctrl_par(p) | (s2 ? C_STOP2 : 32'd0));
    for (int i = 0; i < n; i++) begin
      b = (i == 0) ? (8'hA5 ^ 8'(dv)) : 8'($urandom);
      write(TXDATA, {24'hFFFFFF, b}, 4'h1);  // upper bytes are ignored
    end
    wait_tx(n, (n + 1) * 13 + 20);
    clks(4);
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, $sformatf("STATUS after TX div=%0d par=%b stop2=%b", dv, p, s2));
    write(CTRL, 32'h0);
  endtask

  task tx_fixed(input int unsigned dv, input bit [1:0] p, input bit s2, input bit [7:0] b0, input bit [7:0] b1);
    write(BAUD, dv);
    write(CTRL, C_TXEN | ctrl_par(p) | (s2 ? C_STOP2 : 32'd0));
    write(TXDATA, {24'd0, b0}, 4'h1);
    write(TXDATA, {24'd0, b1}, 4'h1);
    wait_tx(2, 2 * 13 + 20);
    clks(4);
    write(CTRL, 32'h0);
  endtask

  task test_formats();
    $display("%0t: [%s] TX formats: baud 3..15 and 1000, parity none/even/odd, 1/2 stop bits", $time, name);
    item("UART-24");
    tx_case(3,  2'b00, 1'b0, 4);
    tx_case(15, 2'b00, 1'b0, 3);
    tx_fixed(1000, 2'b00, 1'b0, 8'h3C, 8'hC3);
    item("UART-25");
    tx_case(4,  2'b01, 1'b0, 3);
    tx_case(5,  2'b10, 1'b0, 3);
    tx_case(10, 2'b01, 1'b0, 2);
    tx_fixed(6, 2'b01, 1'b0, 8'h07, 8'h03);      // even: parity bits 1, 0
    tx_fixed(6, 2'b10, 1'b0, 8'h07, 8'h03);      // odd:  parity bits 0, 1
    item("UART-26");
    tx_case(7,  2'b00, 1'b1, 3);
    tx_case(9,  2'b01, 1'b1, 3);
    tx_case(12, 2'b10, 1'b1, 3);
  endtask

  task test_busy();
    $display("%0t: [%s] STATUS tx_busy / tx_empty", $time, name);
    item("UART-30");
    write(BAUD, 32'd15);
    write(CTRL, C_TXEN | C_RXEN);
    rd_mask(STATUS, S_TXBUSY | S_TXEMPTY, S_TXEMPTY, "idle: tx_busy = 0, tx_empty = 1");
    write(TXDATA, 32'hC3, 4'h1);
    clks(20);
    rd_mask(STATUS, S_TXBUSY | S_TXEMPTY, S_TXBUSY | S_TXEMPTY, "tx_busy during the frame (FIFO already empty)");
    wait_tx(1, 20);
    clks(2);
    rd_mask(STATUS, S_TXBUSY, 32'h0, "tx_busy low after the frame");
    write(CTRL, 32'h0);
  endtask

  task test_default_baud();
    $display("%0t: [%s] default baud 433 (115200 at 50 MHz)", $time, name);
    item("UART-23");
    tx_fixed(433, 2'b00, 1'b0, 8'h55, 8'hA6);
    // TX and RX at the same time
    write(BAUD, 32'd433);
    write(CTRL, C_TXEN | C_RXEN);
    write(TXDATA, 32'h4B, 4'h1);
    send_ok(8'hD2, 433, 2'b00, 1'b0);
    wait_tx(1, 20);
    rx_wait();
    rd_check(RXDATA, 32'hD2, "RX byte received while transmitting");
    write(CTRL, 32'h0);
  endtask

  task test_fifo();
    bit [7:0] bytes[$];
    $display("%0t: [%s] TX FIFO full, tx_ovf, tx_en = 0", $time, name);
    item("UART-27");
    write(BAUD, 32'd4);
    write(CTRL, 32'h0);
    for (int i = 0; i < 16; i++) bytes.push_back(8'(240 - i * 7));
    foreach (bytes[i]) begin
      write(TXDATA, {24'd0, bytes[i]}, 4'h1);
      if (i == 0) rd_check(STATUS, S_RXEMPTY, "TX FIFO not empty after one write");
    end
    rd_check(STATUS, S_RXEMPTY | S_TXFULL, "TX FIFO full");
    rd_check(ISR, 32'h0, "tx_empty low, no tx_ovf yet");
    item("UART-20");
    write(TXDATA, 32'h00, 4'b1110);
    rd_check(ISR, 32'h0, "no tx_ovf for a write with PSTRB[0] = 0");
    item("UART-28");
    write(TXDATA, 32'h5D, 4'b0001);
    rd_check(ISR, I_TXOVF, "tx_ovf set by a write when full");
    item("UART-29");
    clks(40);
    check(tx_count() == 0 && sb.tx_busy_n == 0, "tx_en = 0: nothing sent");
    rd_check(STATUS, S_RXEMPTY | S_TXFULL, "tx_en = 0: TX FIFO keeps its data");
    item("UART-27");
    write(CTRL, C_TXEN);
    wait_tx(16, 16 * 10 + 20);
    item("UART-28");
    clks(4 * 5 * 10);
    check(tx_count() == 0 && sb.tx_busy_n == 0, "the dropped byte is not sent");
    rd_check(ISR, I_TXEMPTY | I_TXOVF, "tx_ovf stays, tx_empty back");
    item("UART-43");
    write(ISR, I_TXOVF, 4'b1110);
    rd_check(ISR, I_TXEMPTY | I_TXOVF, "tx_ovf not cleared with PSTRB[0] = 0");
    write(ISR, I_TXOVF | I_TXEMPTY | I_RXNE);
    rd_check(ISR, I_TXEMPTY, "tx_ovf cleared by W1C, level bits unchanged");
    write(CTRL, 32'h0);
  endtask

  task test_tx_en();
    $display("%0t: [%s] tx_en cleared during a frame", $time, name);
    item("UART-29");
    write(BAUD, 32'd15);
    write(CTRL, C_EVEN);
    write(TXDATA, 32'hA1, 4'h1);
    write(TXDATA, 32'hB2, 4'h1);
    write(CTRL, C_TXEN | C_EVEN);
    clks(30);
    write(CTRL, C_EVEN);
    rd_mask(STATUS, S_TXBUSY | S_TXEMPTY, S_TXBUSY, "tx_en = 0 in a frame: still busy, byte 2 waits");
    clks(3 * 11 * 16);
    check(tx_count() == 1 && sb.tx_busy_n == 0,
          $sformatf("tx_en = 0 in a frame: %0d frames sent, expected 1", tx_count()));
    tx_seen += tx_count();
    rd_mask(STATUS, S_TXBUSY | S_TXEMPTY, 32'h0, "byte 2 kept in the TX FIFO");
    write(CTRL, C_TXEN | C_EVEN);
    wait_tx(1, 20);
    write(CTRL, 32'h0);
  endtask
endclass
