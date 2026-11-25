// spi_rand_test: random traffic (SPI-RND)
class spi_rand_test extends spi_base_test;
  function new();
    super.new();
    name = "spi_rand_test";
  endfunction

  virtual task run_scenario();
    int n = 20;
    void'($value$plusargs("N=%d", n));
    $display("%0t: [%s] %0d random rounds", $time, name, n);
    item("SPI-RND");
    for (int r = 0; r < n; r++) round(r);
    $display("%0t: [%s] %0d frames, %0d RX bytes lost, %0d TX bytes dropped", $time, name,
             sb.n_frames, sb.n_lost, sb.n_drop);
  endtask

  task round(input int r);
    spi_packet  p = new();
    bit         cpol, cpha, lsb;
    int unsigned dv, n_tx, n_sl;
    bit [31:0]  m, d;
    cpol = 1'($urandom_range(1));
    cpha = 1'($urandom_range(1));
    lsb  = 1'($urandom_range(1));
    dv   = ($urandom_range(7) == 0) ? $urandom_range(20, 8) : $urandom_range(3);
    cfg.miso_dly = $urandom_range(19, 1);
    m    = mode_bits(cpol, cpha, lsb);
    n_tx = $urandom_range(24, 1);
    n_sl = $urandom_range(n_tx);
    $display("%0t: [%s] round %0d: mode %0d%s div=%0d miso_dly=%0d, %0d TX bytes, %0d slave bytes",
             $time, name, r, {cpol, cpha}, lsb ? " LSB" : "", dv, cfg.miso_dly, n_tx, n_sl);
    for (int i = 0; i < n_sl; i++) begin
      if (p.randomize() == 0) check(1'b0, "randomize() failed");
      slave(p.data);
    end
    setup_mode(cpol, cpha, lsb, dv, 1'($urandom_range(4) != 0));
    write(IER, 32'($urandom_range(3)));
    if ($urandom_range(1)) write(CTRL, m | C_EN);

    // phase 1
    apb_traffic(n_tx, m);

    // phase 2
    if (!cfg.en) write(CTRL, m | C_EN);         // send what is left
    wait_idle();
    repeat (sb.rxq.size() + $urandom_range(2)) read(RXDATA, d);
    read(STATUS, d);
    read(ISR, d);
    write(ISR, 32'($urandom_range(3)));
    read(ISR, d);
    write(CTRL, m);
    write(CS, 32'h1);
    write(ISR, 32'h3);
  endtask

  // TX FIFO write allowed: not in the last clocks of a frame with the TX FIFO empty
  function bit tx_ok();
    return !(sb.busy_n != 0 && sb.txq.size() == 0);
  endfunction

  // RXDATA read allowed: not in a frame with the RX FIFO full
  function bit rx_ok();
    return sb.rxq.size() < 16 || sb.busy_n == 0;
  endfunction

  task apb_traffic(input int unsigned n_tx, input bit [31:0] m);
    bit [11:0] ro[6] = '{CTRL, CLKDIV, CS, STATUS, IER, ISR};
    bit [31:0] d;
    int unsigned k = 0, lim = 4000;
    while ((k < n_tx || $urandom_range(3) != 0) && lim > 0) begin
      lim--;
      case ($urandom_range(9))
        0, 1, 2, 3: if (k < n_tx && tx_ok()) begin
          write(TXDATA, $urandom, ($urandom_range(9) == 0) ? 4'b1110 : 4'b0001);
          k++;
        end
        4, 5: if (rx_ok()) read(RXDATA, d);
        6:    write(ISR, 32'($urandom_range(3)));
        7:    if ($urandom_range(3) == 0) write(CTRL, m | (cfg.en ? 32'h0 : C_EN));
        default: read(ro[$urandom_range(5)], d);
      endcase
      clks($urandom_range(3 * (cfg.div + 1)));
    end
  endtask
endclass
