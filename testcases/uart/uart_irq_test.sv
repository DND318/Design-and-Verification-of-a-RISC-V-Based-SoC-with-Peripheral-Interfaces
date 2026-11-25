// uart_irq_test: UART-42..44: interrupts
class uart_irq_test extends uart_base_test;
  function new();
    super.new();
    name = "uart_irq_test";
  endfunction

  virtual task run_scenario();
    $display("%0t: [%s] IER gating of irq_uart_o", $time, name);
    item("UART-42");
    irq_check(1'b0, "after reset");
    // tx_empty (level, ISR = 0x01 now)
    irq_check(1'b0, "IER = 0");
    write(IER, 32'h3E);    irq_check(1'b0, "tx_empty set, tx_empty_ie = 0");
    write(IER, I_TXEMPTY); irq_check(1'b1, "tx_empty and tx_empty_ie");
    item("UART-44");
    write(TXDATA, 32'h12, 4'h1);             // tx_en = 0: FIFO not empty
    irq_check(1'b0, "tx_empty low after a TXDATA write");
    write(IER, 32'h0);
    // rx_ne (level)
    item("UART-42");
    write(BAUD, 32'd3);
    write(CTRL, C_RXEN | C_EVEN);
    send_ok(8'h77, 3, 2'b01, 1'b0);
    rx_wait();
    irq_check(1'b0, "rx_ne with IER = 0");
    write(IER, 32'h3D);    irq_check(1'b0, "rx_ne set, only the other enables");
    write(IER, I_RXNE);    irq_check(1'b1, "rx_ne and rx_ne_ie");
    item("UART-44");
    rd_check(RXDATA, 32'h77, "a pop clears rx_ne");
    irq_check(1'b0, "rx_ne low after the pop");
    // parity_err (W1C)
    item("UART-42");
    write(IER, 32'h3B);
    send_frame(8'h70, 3, 2'b01, 1'b0, 1'b1, 2'b00);
    rx_wait();
    rd_check(RXDATA, 32'h70, "byte with a parity error");
    rd_check(ISR, I_PERR, "only parity_err set (TX FIFO not empty)");
    irq_check(1'b0, "parity_err, parity_err_ie = 0");
    write(IER, I_PERR);    irq_check(1'b1, "parity_err and parity_err_ie");
    item("UART-43");
    write(ISR, I_PERR);    irq_check(1'b0, "parity_err cleared by W1C");
    // frame_err (W1C)
    item("UART-42");
    write(IER, 32'h37);
    send_frame(8'h0F, 3, 2'b01, 1'b0, 1'b0, 2'b01);
    rx_wait();
    wclk(8);
    rd_check(RXDATA, 32'h0F, "byte with a frame error");
    rd_check(ISR, I_FERR, "only frame_err set");
    irq_check(1'b0, "frame_err, frame_err_ie = 0");
    write(IER, I_FERR);    irq_check(1'b1, "frame_err and frame_err_ie");
    item("UART-43");
    write(ISR, I_FERR);    irq_check(1'b0, "frame_err cleared by W1C");
    // overrun (W1C)
    item("UART-42");
    write(IER, 32'h2D);
    for (int i = 0; i < 17; i++) send_ok(8'(i), 3, 2'b01, 1'b0);
    rx_wait();
    rd_check(ISR, I_RXNE | I_OVR, "overrun");
    irq_check(1'b0, "overrun, overrun_ie = 0 (rx_ne_ie = 0)");
    write(IER, I_OVR);     irq_check(1'b1, "overrun and overrun_ie");
    for (int i = 0; i < 16; i++) rd_check(RXDATA, 32'(i), "drain the RX FIFO");
    irq_check(1'b1, "overrun irq stays after the drain");
    item("UART-43");
    write(ISR, I_OVR);     irq_check(1'b0, "overrun cleared by W1C");
    // tx_ovf (W1C)
    item("UART-42");
    write(IER, 32'h1F);
    for (int i = 0; i < 16; i++) write(TXDATA, 32'(i), 4'h1);   // one byte already inside
    rd_check(ISR, I_TXOVF, "tx_ovf");
    irq_check(1'b0, "tx_ovf, tx_ovf_ie = 0");
    write(IER, I_TXOVF);   irq_check(1'b1, "tx_ovf and tx_ovf_ie");
    item("UART-43");
    write(ISR, I_TXOVF);   irq_check(1'b0, "tx_ovf cleared by W1C");
    // drain the TX FIFO: tx_empty comes back
    item("UART-44");
    write(IER, I_TXEMPTY);
    irq_check(1'b0, "tx_empty low, FIFO full");
    write(CTRL, C_TXEN | C_EVEN);
    wait_tx(16, 16 * 11 + 20);
    clks(4);
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "STATUS at the end");
    irq_check(1'b1, "tx_empty irq at the end");
    write(CTRL, 32'h0);
    write(IER, 32'h0);
  endtask
endclass
