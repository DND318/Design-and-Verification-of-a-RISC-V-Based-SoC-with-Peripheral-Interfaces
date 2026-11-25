// uart_rand_test: random traffic (UART-RND)
class uart_rand_test extends uart_base_test;
  function new();
    super.new();
    name = "uart_rand_test";
  endfunction

  virtual task run_scenario();
    int n = 30;
    void'($value$plusargs("N=%d", n));
    $display("%0t: [%s] %0d random rounds", $time, name, n);
    item("UART-RND");
    for (int r = 0; r < n; r++) round(r);
    $display("%0t: [%s] %0d TX frames, %0d RX frames", $time, name, sb.n_tx_frames, sb.n_rx_frames);
  endtask

  task round(input int r);
    uart_packet cfg_p = new();
    bit [31:0]  ctrl, d;
    bit         tx_en, rx_en, loop;
    int         n_tx, n_rx;
    if (cfg_p.randomize() == 0) check(1'b0, "randomize() failed");
    if (r % 10 == 9) cfg_p.div = $urandom_range(80, 40);   // a few slower rounds
    tx_en = ($urandom_range(9) != 0);
    rx_en = ($urandom_range(9) != 0);
    loop  = ($urandom_range(5) == 0);
    ctrl  = {26'd0, loop, cfg_p.stop2, cfg_p.par, rx_en, tx_en};
    n_tx  = $urandom_range(tx_en ? 12 : 18);
    n_rx  = loop ? $urandom_range(1) : $urandom_range(10);
    $display("%0t: [%s] round %0d: div=%0d par=%b stop2=%b tx_en=%b rx_en=%b loop=%b, %0d TX bytes, %0d RX frames",
             $time, name, r, cfg_p.div, cfg_p.par, cfg_p.stop2, tx_en, rx_en, loop, n_tx, n_rx);
    write(BAUD, cfg_p.div);
    write(CTRL, ctrl);
    write(IER, 32'($urandom_range(63)));

    // phase 1: APB and serial traffic at the same time
    fork
      apb_traffic(n_tx, tx_en);
      line_traffic(n_rx, cfg_p.div, cfg_p.par, cfg_p.stop2);
    join
    wait_idle();

    // phase 2: drain the RX FIFO, clear the flags
    repeat (sb.rxq.size() + $urandom_range(2)) read(RXDATA, d);
    read(STATUS, d);
    read(ISR, d);
    write(ISR, 32'($urandom_range(63)));
    read(ISR, d);
    if (!tx_en) begin                            // send what is left, then switch off
      write(CTRL, ctrl | C_TXEN);
      wait_idle();
    end
    write(CTRL, 32'h0);
    write(ISR, 32'h3F);
  endtask

  // TXDATA writes and side-effect-free reads with random gaps. With tx_en = 1
  // the FIFO is never filled, so a write cannot meet a pop at the full limit.
  task apb_traffic(input int n_tx, input bit tx_en);
    bit [11:0] ro[5] = '{CTRL, BAUD, STATUS, IER, ISR};
    bit [31:0] d;
    int        k = 0;
    while (k < n_tx || $urandom_range(3) != 0) begin
      if (k < n_tx && $urandom_range(1)) begin
        if (!tx_en || sb.txq.size() < 14) begin
          write(TXDATA, $urandom, ($urandom_range(7) == 0) ? 4'b1110 : 4'b0001);
          k++;
        end
      end else begin
        read(ro[$urandom_range(4)], d);
      end
      clks($urandom_range(30));
    end
  endtask

  // Frames on uart_rx_i in the format of the receiver, with random errors.
  // After a 0 stop bit the line stays idle for two bits, so the receiver is
  // not inside a false start when the next frame begins.
  task line_traffic(input int n_rx, input int unsigned dv, input bit [1:0] p, input bit s2);
    uart_packet f;
    for (int i = 0; i < n_rx; i++) begin
      f = new();
      if (f.randomize() == 0) check(1'b0, "randomize() failed");
      f.kind = UART_FRAME;
      f.div = dv; f.par = p; f.stop2 = s2;
      if ($urandom_range(3) == 0) f.data = ($urandom_range(1)) ? 8'h00 : 8'hFF;
      f.bad_par  = (p != 2'b00) && ($urandom_range(7) == 0);
      f.bad_stop = ($urandom_range(7) == 0) ? 2'($urandom_range(3, 1)) : 2'b00;
      if (!s2) f.bad_stop[1] = 1'b0;
      ustim.send(f);
      if (f.bad_stop != 2'b00) wclk(2 * (dv + 1));
      else                     wclk($urandom_range(3 * (dv + 1)));
    end
  endtask
endclass
