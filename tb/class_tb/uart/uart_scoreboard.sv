// UART scoreboard (reference model)
class uart_scoreboard;
  mailbox #(apb_packet)  apb_m2s_mb;
  mailbox #(uart_packet) uart_m2s_mb;
  uart_cfg               cfg;

  // reference model
  bit [5:0]        ier;
  bit              perr, ferr, ovr, txovf;
  bit [7:0]        txq[$];        // bytes waiting in the TX FIFO
  time             txq_t[$];      // time each of them was written
  bit [7:0]        tx_cur[$];     // bytes on the line (started, not yet checked)
  bit [7:0]        rxq[$];        // bytes in the RX FIFO
  int              tx_busy_n, rx_busy_n;
  longint unsigned last_start_cyc, last_len;
  time             last_end_t;    // end of the frame on the line (start time + length)
  time             t_last_txwr;   // time of the last TXDATA write

  // statistics
  int unsigned     n_xfer, n_rd, n_tx_frames, n_rx_frames, n_rx_lost, n_false, n_err;
  bit              verbose;
  bit              en_fc = 1'b1;
  `include "coverage.sv"

  function new(mailbox #(apb_packet) apb_m2s_mb, mailbox #(uart_packet) uart_m2s_mb, uart_cfg cfg);
    this.apb_m2s_mb  = apb_m2s_mb;
    this.uart_m2s_mb = uart_m2s_mb;
    this.cfg         = cfg;
    verbose = $test$plusargs("VERBOSE");
    reset();
`ifndef VERILATOR
    APB_GROUP = new();   // embedded covergroups are created in the constructor
    FRAME_GROUP = new();
    IRQ_GROUP = new();
`endif
  endfunction

  function void reset();
    cfg.div = 433; cfg.par = 2'b00; cfg.stop2 = 1'b0;
    cfg.tx_en = 1'b0; cfg.rx_en = 1'b0; cfg.loopback = 1'b0;
    ier = 6'd0;
    {perr, ferr, ovr, txovf} = 4'b0;
    txq.delete(); txq_t.delete(); tx_cur.delete(); rxq.delete();
  endfunction

  function void check(bit ok, string what);
    if (!ok) n_err++;
    vplan_pkg::chk(ok, what);
  endfunction

  // No frame in progress and none about to start: STATUS / ISR / irq are stable
  function bit quiet();
    return tx_busy_n == 0 && rx_busy_n == 0 && !(cfg.tx_en && txq.size() != 0);
  endfunction

  function bit [5:0] isr();
    return {txovf, ovr, ferr, perr, rxq.size() != 0, txq.size() == 0};
  endfunction

  function bit [31:0] status();
    return {28'd0, rxq.size() == 0, rxq.size() == 16, txq.size() == 0, txq.size() == 16};
  endfunction

  task run();
    fork
      apb_run();
      uart_run();
    join
  endtask

  // ---------------------------------------------------------------- APB side
  task apb_run();
    apb_packet p;
    forever begin
      apb_m2s_mb.get(p);
      check_apb(p);
    end
  endtask

  function void check_apb(apb_packet p);
    bit [31:0] exp;
    bit        cmp = 1'b1;
    if (!p.rst_n) begin
      reset();
      tx_busy_n = 0;
      rx_busy_n = 0;
      return;
    end
    // irq pin: the value at this edge comes from the state before this edge
    if (quiet())
      check(p.irq[0] === |(isr() & ier),
            $sformatf("[scoreboard] irq_uart_o = %b, model expects %b (ISR %h, IER %h)",
                      p.irq[0], |(isr() & ier), isr(), ier));
    if (!p.xfer) return;
    n_xfer++;
    if (en_fc) sample_apb_fc(p);
    check(p.pready && !p.pslverr, $sformatf("[scoreboard] %s: PREADY=%b PSLVERR=%b", p.sprint(), p.pready, p.pslverr));
    if (!p.write) begin
      case (p.addr[11:2])
        10'd0: exp = {26'd0, cfg.loopback, cfg.stop2, cfg.par, cfg.rx_en, cfg.tx_en};
        10'd1: exp = {16'd0, 16'(cfg.div)};
        10'd2: begin                    // busy bits are 0 when quiet
          exp = status();
          cmp = quiet();
        end
        10'd3: exp = 32'd0;
        10'd4: begin
          exp = (rxq.size() != 0) ? {24'd0, rxq.pop_front()} : 32'd0;
        end
        10'd5: exp = {26'd0, ier};
        10'd6: begin
          exp = {26'd0, isr()};
          cmp = quiet();
          if (cmp && en_fc) sample_irq_fc(ier, isr());
        end
        default: exp = 32'd0;
      endcase
      if (cmp) begin
        n_rd++;
        check(p.rdata === exp, $sformatf("[scoreboard] read %h = %h, model expects %h", p.addr, p.rdata, exp));
      end
      if (verbose) $display("%0t: [scoreboard] Get packet from monitor: %s%s", $time, p.sprint(),
                            cmp ? "" : " (not compared: frame in progress)");
      return;
    end
    if (verbose) $display("%0t: [scoreboard] Get packet from monitor: %s", $time, p.sprint());
    case (p.addr[11:2])
      10'd0: if (p.strb[0]) begin
        cfg.tx_en    = p.data[0];
        cfg.rx_en    = p.data[1];
        cfg.stop2    = p.data[4];
        cfg.loopback = p.data[5];
        if (p.data[3:2] != 2'b11) cfg.par = p.data[3:2];
      end
      10'd1: begin
        if (p.strb[0]) cfg.div[7:0]  = p.data[7:0];
        if (p.strb[1]) cfg.div[15:8] = p.data[15:8];
      end
      10'd3: if (p.strb[0]) begin
        t_last_txwr = $time;
        if (txq.size() < 16) begin
          txq.push_back(p.data[7:0]);
          txq_t.push_back($time);
        end else begin
          txovf = 1'b1;
        end
      end
      10'd5: if (p.strb[0]) ier = p.data[5:0];
      10'd6: if (p.strb[0]) begin
        if (p.data[2]) perr  = 1'b0;
        if (p.data[3]) ferr  = 1'b0;
        if (p.data[4]) ovr   = 1'b0;
        if (p.data[5]) txovf = 1'b0;
      end
      default: ;
    endcase
  endfunction

  // ---------------------------------------------------------------- serial side
  task uart_run();
    uart_packet p;
    forever begin
      uart_m2s_mb.get(p);
      if (verbose) $display("%0t: [scoreboard] Get packet from monitor: %s", $time, p.sprint());
      check_uart(p);
    end
  endtask

  function void rx_push(bit [7:0] d, bit pe, bit fe);
    if (pe) perr = 1'b1;
    if (fe) ferr = 1'b1;
    if (rxq.size() < 16) begin
      rxq.push_back(d);
    end else begin
      ovr = 1'b1;
      n_rx_lost++;
    end
  endfunction

  function void check_uart(uart_packet p);
    case (p.kind)
      UART_TX_START: begin
        time t_wr = 0;
        check(cfg.tx_en, "[scoreboard] TX frame started while tx_en = 0");
        check(txq.size() != 0, "[scoreboard] TX frame started with an empty TX FIFO");
        if (txq.size() != 0) begin
          tx_cur.push_back(txq.pop_front());
          t_wr = txq_t.pop_front();
        end
        // the byte was already waiting before the previous frame ended:
        // back-to-back, no idle time between the frames
        if (tx_busy_n != 0 && t_wr + 2 * cfg.clk_ns <= last_end_t)
          check(p.cyc - last_start_cyc == last_len,
                $sformatf("[scoreboard] back-to-back TX frames %0d clocks apart, expected %0d",
                          p.cyc - last_start_cyc, last_len));
        tx_busy_n++;
        last_start_cyc = p.cyc;
        last_len       = p.nbits * (p.div + 1);
        last_end_t     = $time + last_len * cfg.clk_ns;
      end
      UART_TX_FRAME: begin
        bit [7:0] exp;
        tx_busy_n--;
        n_tx_frames++;
        if (en_fc) sample_frame_fc(p);
        check(p.fmt_ok, $sformatf("[scoreboard] %s: bad frame format (bit length, start, parity or stop bit)",
                                  p.sprint()));
        if (cfg.loopback) check(p.pin_idle,   "[scoreboard] uart_tx_o moved in loopback");
        else              check(p.pin_follow, "[scoreboard] uart_tx_o differs from the transmitter output");
        exp = (tx_cur.size() != 0) ? tx_cur.pop_front() : 8'h00;
        check(p.data === exp, $sformatf("[scoreboard] TX byte %h, model expects %h", p.data, exp));
        if (cfg.loopback && cfg.rx_en) rx_push(p.data, 1'b0, 1'b0);
        // a byte that was waiting when the frame ended must already be on the line
        // (unless it was written during the last few clocks)
        if (cfg.tx_en && txq.size() != 0 && tx_busy_n == 0 && $time - t_last_txwr > 10 * cfg.clk_ns)
          check(1'b0, "[scoreboard] TX FIFO not empty but no back-to-back frame");
      end
      UART_RX_START: rx_busy_n++;
      UART_RX_FALSE: begin
        rx_busy_n--;
        n_false++;
      end
      UART_RX_FRAME: begin
        rx_busy_n--;
        n_rx_frames++;
        if (en_fc) sample_frame_fc(p);
        if (cfg.rx_en && !cfg.loopback) rx_push(p.data, p.perr, p.ferr);
      end
      default: ;
    endcase
  endfunction

  function void report();
    $display("%0t: [scoreboard] %0d transfers, %0d reads compared, %0d TX frames, %0d RX frames (%0d lost), %0d false starts, %0d mismatches",
             $time, n_xfer, n_rd, n_tx_frames, n_rx_frames, n_rx_lost, n_false, n_err);
    report_fc();
  endfunction
endclass
