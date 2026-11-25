// UART monitor
class uart_monitor;
  virtual uart_if        dut_vif;
  mailbox #(uart_packet) m2s_mb;
  uart_cfg               cfg;
  longint unsigned       cyc;          // falling clock edges since time 0

  function new(virtual uart_if dut_vif, mailbox #(uart_packet) m2s_mb, uart_cfg cfg);
    this.dut_vif = dut_vif;
    this.m2s_mb  = m2s_mb;
    this.cfg     = cfg;
  endfunction

  task run();
    fork
      count_cycles();
      tx_run();
      rx_run();
    join
  endtask

  task count_cycles();
    while (1) begin
      @(negedge dut_vif.clk);
      cyc++;
    end
  endtask

  function uart_packet new_pkt(uart_kind_e k);
    uart_packet pkt = new();
    pkt.kind  = k;
    pkt.cyc   = cyc;
    pkt.div   = cfg.div;
    pkt.par   = cfg.par;
    pkt.stop2 = cfg.stop2;
    pkt.nbits = pkt.frame_bits();
    return pkt;
  endfunction

  function void report(uart_packet pkt);
    $display("%0t: [uart_monitor] %s", $time, pkt.sprint());
    m2s_mb.put(pkt);
  endfunction

  // End of a frame: reported LATE clocks later, in the background, so the
  // DUT (2-flop synchronizer, sampling in the middle of the stop bit, FIFO
  // write) has stored or sent it before the scoreboard counts it, while the
  // monitor is already waiting for the next start bit.
  localparam int LATE = 6;
  task report_late(uart_packet pkt);
    fork
      begin
        automatic uart_packet q = pkt;
        for (int k = 0; k < LATE; k++) @(negedge dut_vif.clk);
        report(q);
      end
    join_none
  endtask

  // ---------------------------------------------------------------- TX side
  task tx_run();
    while (1) begin
      do begin
        @(negedge dut_vif.tx_ser);
      end while (dut_vif.tx_ser !== 1'b0);
      @(negedge dut_vif.clk);                    // first clock of the start bit
      $display("%0t: [uart_monitor] TX start bit detect", $time);
      tx_frame();
    end
  endtask

  task tx_frame();
    uart_packet  f  = new_pkt(UART_TX_FRAME);
    int unsigned bt = f.div + 1;
    int unsigned nb = f.nbits;
    logic        first, v, mid [12];
    bit          stable = 1'b1;
    report(new_pkt(UART_TX_START));
    f.pin_follow = 1'b1;
    f.pin_idle   = 1'b1;
    for (int unsigned idx = 0; idx < nb * bt; idx++) begin
      if (idx != 0) @(negedge dut_vif.clk);
      v = dut_vif.tx_ser;
      if (dut_vif.tx !== v)    f.pin_follow = 1'b0;
      if (dut_vif.tx !== 1'b1) f.pin_idle   = 1'b0;
      if (idx % bt == 0)       first = v;
      else if (v !== first)    stable = 1'b0;
      if (idx % bt == bt / 2)  mid[idx / bt] = v;
    end
    for (int i = 0; i < 8; i++) f.data[i] = mid[i + 1];
    f.fmt_ok = stable && (mid[0] === 1'b0);
    if (f.par != 2'b00) begin
      f.perr   = (mid[9] !== uart_packet::par_bit(f.data, f.par));
      f.fmt_ok = f.fmt_ok && !f.perr;
    end
    f.ferr   = (mid[nb - 1] !== 1'b1) || (f.stop2 && mid[nb - 2] !== 1'b1);
    f.fmt_ok = f.fmt_ok && !f.ferr && !$isunknown(f.data);
    report_late(f);
  endtask

  // ---------------------------------------------------------------- RX side
  task rx_run();
    while (1) begin
      do begin
        @(negedge dut_vif.rx);
      end while (dut_vif.rx !== 1'b0);
      @(negedge dut_vif.clk);                    // first clock of the start bit
      $display("%0t: [uart_monitor] RX start bit detect", $time);
      rx_frame();
    end
  endtask

  task rx_frame();
    uart_packet  f  = new_pkt(UART_RX_FRAME);
    int unsigned bt = f.div + 1;
    int unsigned nb = f.nbits;
    logic        mid [12];
    report(new_pkt(UART_RX_START));
    for (int unsigned idx = 0; idx < nb * bt; idx++) begin
      if (idx != 0) @(negedge dut_vif.clk);
      if (idx % bt == bt / 2) begin
        mid[idx / bt] = dut_vif.rx;
        if (idx / bt == 0 && dut_vif.rx !== 1'b0) begin
          report(new_pkt(UART_RX_FALSE));
          return;
        end
      end
    end
    for (int i = 0; i < 8; i++) f.data[i] = mid[i + 1];
    if (f.par != 2'b00) f.perr = (mid[9] !== uart_packet::par_bit(f.data, f.par));
    f.ferr = (mid[f.par != 2'b00 ? 10 : 9] !== 1'b1) || (f.stop2 && mid[nb - 1] !== 1'b1);
    report_late(f);
  endtask
endclass
