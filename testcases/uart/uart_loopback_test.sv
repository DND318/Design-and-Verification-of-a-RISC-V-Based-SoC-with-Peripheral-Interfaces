// uart_loopback_test: UART-41: loopback
class uart_loopback_test extends uart_base_test;
  function new();
    super.new();
    name = "uart_loopback_test";
  endfunction

  virtual task run_scenario();
    loop_case(5, C_ODD | C_STOP2, 2'b10, 1'b1, 5);
    loop_case(9, C_EVEN,          2'b01, 1'b0, 4);
    loop_case(3, 32'h0,           2'b00, 1'b0, 6);
  endtask

  task loop_case(input int unsigned dv, input bit [31:0] fmt, input bit [1:0] p, input bit s2,
                 input int unsigned n);
    bit [7:0] bytes[$];
    $display("%0t: [%s] loopback div=%0d par=%b stop2=%b, %0d bytes", $time, name, dv, p, s2, n);
    item("UART-41");
    write(BAUD, dv);
    write(CTRL, C_TXEN | C_RXEN | C_LOOP | fmt);
    clks(2);
    for (int i = 0; i < n; i++) bytes.push_back(8'(8'h11 * (i + 3)) ^ 8'(dv));
    foreach (bytes[i]) write(TXDATA, {24'd0, bytes[i]}, 4'h1);
    // a frame on uart_rx_i must be ignored in loopback
    send_ok(8'hEE, dv, p, s2);
    wait_tx(n, n * 13 + 20);
    rx_wait();
    clks(4);
    foreach (bytes[i]) rd_check(RXDATA, {24'd0, bytes[i]}, $sformatf("loopback byte %0d", i));
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "loopback: FIFOs empty, engines idle");
    rd_check(ISR, I_TXEMPTY, "loopback: no error flag");
    write(CTRL, 32'h0);
  endtask
endclass
