// uart_rx_test: UART-31..40: receiver
class uart_rx_test extends uart_base_test;
  function new();
    super.new();
    name = "uart_rx_test";
  endfunction

  virtual task run_scenario();
    test_formats();
    test_busy();
    test_default_baud();
    test_false_start();
    test_sampling();
    test_frame_error();
    test_parity_error();
    test_fifo();
    test_rx_en();
  endtask

  // Program one line setting, send n frames back to back, read them back
  task rx_case(input int unsigned dv, input bit [1:0] p, input bit s2, input int unsigned n);
    bit [7:0] b[$];
    write(BAUD, dv);
    write(CTRL, C_RXEN | ctrl_par(p) | (s2 ? C_STOP2 : 32'd0));
    for (int i = 0; i < n; i++) b.push_back(8'($urandom));
    b[0] = 8'h5A ^ 8'(dv);
    foreach (b[i]) send_ok(b[i], dv, p, s2);
    rx_wait();
    rd_mask(STATUS, S_RXEMPTY | S_RXBUSY, 32'h0, $sformatf("RX div=%0d: STATUS not empty", dv));
    foreach (b[i])
      rd_check(RXDATA, {24'd0, b[i]}, $sformatf("RX div=%0d par=%b stop2=%b byte %0d", dv, p, s2, i));
    rd_mask(STATUS, S_RXEMPTY, S_RXEMPTY, "RX FIFO empty after the reads");
    rd_check(ISR, I_TXEMPTY, $sformatf("RX div=%0d par=%b: no error flag", dv, p));
  endtask

  task test_formats();
    $display("%0t: [%s] RX formats: baud 3..15, parity none/even/odd, 1/2 stop bits", $time, name);
    item("UART-31");
    rx_case(3,  2'b00, 1'b0, 4);
    rx_case(7,  2'b00, 1'b1, 3);
    rx_case(15, 2'b00, 1'b0, 3);
    item("UART-32");
    rx_case(4,  2'b01, 1'b0, 3);
    rx_case(6,  2'b10, 1'b0, 3);
    rx_case(8,  2'b01, 1'b1, 3);
    rx_case(11, 2'b10, 1'b1, 3);
  endtask

  task test_busy();
    $display("%0t: [%s] STATUS rx_busy / rx_empty", $time, name);
    item("UART-40");
    write(BAUD, 32'd15);
    write(CTRL, C_RXEN);
    rd_mask(STATUS, S_RXBUSY | S_RXEMPTY, S_RXEMPTY, "idle: rx_busy = 0, rx_empty = 1");
    fork
      send_ok(8'h3C, 15, 2'b00, 1'b0);
      begin
        clks(40);
        rd_mask(STATUS, S_RXBUSY | S_RXEMPTY, S_RXBUSY | S_RXEMPTY, "rx_busy during the frame");
      end
    join
    rx_wait();
    rd_mask(STATUS, S_RXBUSY | S_RXEMPTY, 32'h0, "rx_busy low, byte in the FIFO");
    rd_check(RXDATA, 32'h3C, "busy test byte");
  endtask

  task test_default_baud();
    $display("%0t: [%s] default baud 433 (115200 at 50 MHz)", $time, name);
    item("UART-31");
    write(BAUD, 32'd433);
    write(CTRL, C_RXEN);
    send_ok(8'h55, 433, 2'b00, 1'b0);
    send_ok(8'hA6, 433, 2'b00, 1'b0);
    send_ok(8'h00, 433, 2'b00, 1'b0);
    send_ok(8'hFF, 433, 2'b00, 1'b0);
    rx_wait();
    rd_check(RXDATA, 32'h55, "RX 433 byte 0");
    rd_check(RXDATA, 32'hA6, "RX 433 byte 1");
    rd_check(RXDATA, 32'h00, "RX 433 byte 2");
    rd_check(RXDATA, 32'hFF, "RX 433 byte 3");
    rd_check(ISR, I_TXEMPTY, "RX 433: no error flag");
  endtask

  task test_false_start();
    $display("%0t: [%s] false start rejection", $time, name);
    item("UART-36");
    write(BAUD, 32'd15);
    write(CTRL, C_RXEN);
    send_glitch(1);                              // one clock
    wclk(3 * 16);
    send_glitch(5);                              // shorter than half a bit
    wclk(3 * 16);
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "false start: nothing received, receiver idle");
    rd_check(ISR, I_TXEMPTY, "false start: no flag");
    send_ok(8'h96, 15, 2'b00, 1'b0);
    rx_wait();
    rd_check(RXDATA, 32'h96, "frame after the false starts");
    rd_mask(STATUS, S_RXEMPTY, S_RXEMPTY, "only one byte after the false starts");
  endtask

  task test_sampling();
    $display("%0t: [%s] mid-bit sampling with skewed edges", $time, name);
    item("UART-37");
    write(BAUD, 32'd15);
    write(CTRL, C_RXEN);
    send_skew(8'hA5, 15, 4);
    send_skew(8'h5A, 15, -4);
    send_skew(8'h0F, 15, 4);
    rx_wait();
    rd_check(RXDATA, 32'hA5, "skewed edges +4/-4: byte A5");
    rd_check(RXDATA, 32'h5A, "skewed edges -4/+4: byte 5A");
    rd_check(RXDATA, 32'h0F, "skewed edges +4/-4: byte 0F");
    rd_check(ISR, I_TXEMPTY, "skewed edges: no error flag");
  endtask

  task test_frame_error();
    $display("%0t: [%s] frame error", $time, name);
    item("UART-34");
    write(BAUD, 32'd7);
    write(CTRL, C_RXEN);
    send_frame(8'h81, 7, 2'b00, 1'b0, 1'b0, 2'b01);
    rx_wait();
    wclk(8);                                     // the 0 stop bit may look like a false start
    rd_check(ISR, I_TXEMPTY | I_RXNE | I_FERR, "frame_err set, byte stored");
    rd_check(RXDATA, 32'h81, "byte with a frame error is stored");
    item("UART-43");
    write(ISR, I_FERR, 4'b1110);
    rd_check(ISR, I_TXEMPTY | I_FERR, "frame_err not cleared with PSTRB[0] = 0");
    write(ISR, 32'h0, 4'b0001);
    rd_check(ISR, I_TXEMPTY | I_FERR, "frame_err not cleared by writing 0");
    write(ISR, I_FERR, 4'b0001);
    rd_check(ISR, I_TXEMPTY, "frame_err cleared by W1C");
    item("UART-35");
    write(CTRL, C_RXEN | C_STOP2);
    send_frame(8'h42, 7, 2'b00, 1'b1, 1'b0, 2'b10);
    rx_wait();
    wclk(8);
    rd_check(ISR, I_TXEMPTY | I_RXNE | I_FERR, "frame_err on the second stop bit");
    rd_check(RXDATA, 32'h42, "byte with a bad second stop bit");
    write(ISR, I_FERR);
    send_ok(8'h24, 7, 2'b00, 1'b1);
    rx_wait();
    rd_check(ISR, I_TXEMPTY | I_RXNE, "good 2-stop frame: no frame_err");
    rd_check(RXDATA, 32'h24, "good 2-stop byte");
  endtask

  task test_parity_error();
    $display("%0t: [%s] parity error (even and odd)", $time, name);
    item("UART-33");
    write(CTRL, C_RXEN | C_EVEN);
    send_frame(8'h37, 7, 2'b01, 1'b0, 1'b1, 2'b00);
    rx_wait();
    rd_check(ISR, I_TXEMPTY | I_RXNE | I_PERR, "parity_err, even parity");
    rd_check(RXDATA, 32'h37, "byte with an even parity error is stored");
    item("UART-43");
    write(ISR, 32'hFFFF_FFFF, 4'b1110);
    rd_check(ISR, I_TXEMPTY | I_PERR, "parity_err not cleared with PSTRB[0] = 0");
    write(ISR, I_PERR);
    rd_check(ISR, I_TXEMPTY, "parity_err cleared");
    item("UART-32");
    write(CTRL, C_RXEN | C_ODD);
    send_ok(8'h37, 7, 2'b10, 1'b0);
    rx_wait();
    rd_check(ISR, I_TXEMPTY | I_RXNE, "odd parity correct");
    rd_check(RXDATA, 32'h37, "odd parity byte");
    item("UART-33");
    send_frame(8'hF0, 7, 2'b10, 1'b0, 1'b1, 2'b00);
    rx_wait();
    rd_check(ISR, I_TXEMPTY | I_RXNE | I_PERR, "parity_err, odd parity");
    rd_check(RXDATA, 32'hF0, "byte with an odd parity error is stored");
    send_ok(8'h01, 7, 2'b01, 1'b0);              // even frame into an odd receiver
    rx_wait();
    rd_check(RXDATA, 32'h01, "even frame into an odd receiver");
    rd_mask(ISR, I_PERR, I_PERR, "parity_err still set");
    write(ISR, 32'h3F);
    rd_check(ISR, I_TXEMPTY, "all flags cleared");
  endtask

  task test_fifo();
    bit [7:0] bytes[$];
    $display("%0t: [%s] RX FIFO full, overrun, read when empty", $time, name);
    write(CTRL, C_RXEN);
    write(BAUD, 32'd3);
    item("UART-22");
    rd_check(RXDATA, 32'h0, "RXDATA read when empty returns 0");
    item("UART-38");
    for (int i = 0; i < 16; i++) bytes.push_back(8'(i * 13 + 7));
    foreach (bytes[i]) send_ok(bytes[i], 3, 2'b00, 1'b0);
    rx_wait();
    rd_check(STATUS, S_TXEMPTY | S_RXFULL, "RX FIFO full");
    rd_check(ISR, I_TXEMPTY | I_RXNE, "no overrun yet");
    send_ok(8'hBD, 3, 2'b00, 1'b0);
    rx_wait();
    rd_check(ISR, I_TXEMPTY | I_RXNE | I_OVR, "overrun set");
    rd_check(STATUS, S_TXEMPTY | S_RXFULL, "RX FIFO still full");
    foreach (bytes[i]) rd_check(RXDATA, {24'd0, bytes[i]}, $sformatf("RX FIFO entry %0d", i));
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "RX FIFO empty, the lost byte was not stored");
    rd_check(RXDATA, 32'h0, "lost byte not in the FIFO");
    rd_check(ISR, I_TXEMPTY | I_OVR, "overrun stays until cleared");
    write(ISR, I_OVR);
    rd_check(ISR, I_TXEMPTY, "overrun cleared");
    item("UART-21");
    send_ok(8'h6E, 3, 2'b00, 1'b0);
    rx_wait();
    apb_setup_only(RXDATA, 1'b0, 32'h0);
    rd_check(RXDATA, 32'h6E, "RXDATA not popped by a SETUP phase");
    rd_mask(STATUS, S_RXEMPTY, S_RXEMPTY, "RX FIFO empty after one pop");
  endtask

  task test_rx_en();
    $display("%0t: [%s] rx_en = 0 ignores frames", $time, name);
    item("UART-39");
    write(CTRL, 32'h0);
    fork
      send_ok(8'h99, 3, 2'b00, 1'b0);
      begin
        clks(8);
        rd_mask(STATUS, S_RXBUSY, 32'h0, "rx_busy stays 0 when the receiver is off");
      end
    join
    rx_wait();
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "receiver off: nothing stored");
    rd_check(ISR, I_TXEMPTY, "receiver off: no flag");
  endtask
endclass
