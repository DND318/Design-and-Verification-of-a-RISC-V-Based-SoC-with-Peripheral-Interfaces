// SPI scoreboard (reference model)
class spi_scoreboard;
  mailbox #(apb_packet) apb_m2s_mb;
  mailbox #(spi_packet) spi_m2s_mb;
  spi_cfg               cfg;

  // reference model
  bit [1:0]        ier;
  bit              done, rx_ovr;
  bit [7:0]        txq[$];        // bytes waiting in the TX FIFO
  time             txq_t[$];      // time each of them was written
  bit [7:0]        tx_cur[$];     // byte of the frame on the line
  bit [7:0]        rxq[$];        // bytes in the RX FIFO
  int              busy_n;        // frames started and not yet ended
  time             t_en_on;       // spi_en last set
  time             hold_until;    // a frame may have started just before spi_en was cleared

  // statistics
  int unsigned     n_xfer, n_rd, n_frames, n_lost, n_drop, n_err;
  bit              verbose;
  bit              en_fc = 1'b1;
  `include "coverage.sv"

  function new(mailbox #(apb_packet) apb_m2s_mb, mailbox #(spi_packet) spi_m2s_mb, spi_cfg cfg);
    this.apb_m2s_mb = apb_m2s_mb;
    this.spi_m2s_mb = spi_m2s_mb;
    this.cfg        = cfg;
    verbose = $test$plusargs("VERBOSE");
    reset();
`ifndef VERILATOR
    APB_GROUP   = new();   // embedded covergroups are created in the constructor
    FRAME_GROUP = new();
    IRQ_GROUP   = new();
`endif
  endfunction

  function void reset();
    cfg.en = 0; cfg.cpol = 0; cfg.cpha = 0; cfg.lsb = 0; cfg.div = 1; cfg.cs = 1;
    ier = 2'b00;
    done = 0; rx_ovr = 0;
    txq.delete(); txq_t.delete(); tx_cur.delete(); rxq.delete();
    busy_n = 0;
    hold_until = 0;
  endfunction

  function void check(bit ok, string what);
    if (!ok) n_err++;
    vplan_pkg::chk(ok, what);
  endfunction

  // No frame in progress and none about to start: STATUS / ISR / irq are stable
  function bit quiet();
    return busy_n == 0 && !(cfg.en && txq.size() != 0) && $time >= hold_until;
  endfunction

  function bit [1:0] isr();
    return {rx_ovr, done};
  endfunction

  function bit [31:0] status();
    return {27'd0, rxq.size() == 0, rxq.size() == 16, txq.size() == 0, txq.size() == 16, 1'b0};
  endfunction

  task run();
    fork
      apb_run();
      spi_run();
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
      return;
    end
    // irq pin: the value at this edge comes from the state before this edge
    if (quiet())
      check(p.irq[0] === |(isr() & ier),
            $sformatf("[scoreboard] irq_spi_o = %b, model expects %b (ISR %h, IER %h)",
                      p.irq[0], |(isr() & ier), isr(), ier));
    if (!p.xfer) return;
    n_xfer++;
    if (en_fc) sample_apb_fc(p);
    check(p.pready && !p.pslverr, $sformatf("[scoreboard] %s: PREADY=%b PSLVERR=%b", p.sprint(), p.pready, p.pslverr));
    if (!p.write) begin
      case (p.addr[11:2])
        10'd0: exp = {28'd0, cfg.lsb, cfg.cpha, cfg.cpol, cfg.en};
        10'd1: exp = {24'd0, 8'(cfg.div)};
        10'd2: exp = {31'd0, cfg.cs};
        10'd3: begin
          exp = status();
          cmp = quiet();
        end
        10'd4: exp = 32'd0;
        10'd5: exp = (rxq.size() != 0) ? {24'd0, rxq.pop_front()} : 32'd0;
        10'd6: exp = {30'd0, ier};
        10'd7: begin
          exp = {30'd0, isr()};
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
    if (!p.strb[0]) return;                        // every field is in byte 0
    case (p.addr[11:2])
      10'd0: begin
        if (cfg.en && !p.data[0] && txq.size() != 0)
          hold_until = $time + (cfg.div + 4) * cfg.clk_ns;
        if (!cfg.en && p.data[0]) t_en_on = $time;
        cfg.en   = p.data[0];
        cfg.cpol = p.data[1];
        cfg.cpha = p.data[2];
        cfg.lsb  = p.data[3];
      end
      10'd1: cfg.div = p.data[7:0];
      10'd2: cfg.cs  = p.data[0];
      10'd4: begin
        if (txq.size() < 16) begin
          txq.push_back(p.data[7:0]);
          txq_t.push_back($time);
        end else begin
          n_drop++;
        end
      end
      10'd6: ier = p.data[1:0];
      10'd7: begin
        if (p.data[0]) done   = 1'b0;
        if (p.data[1]) rx_ovr = 1'b0;
      end
      default: ;
    endcase
  endfunction

  // ---------------------------------------------------------------- SPI side
  task spi_run();
    spi_packet p;
    forever begin
      spi_m2s_mb.get(p);
      if (verbose) $display("%0t: [scoreboard] Get packet from monitor: %s", $time, p.sprint());
      check_spi(p);
    end
  endtask

  function void check_spi(spi_packet p);
    case (p.kind)
      SPI_START: begin
        time t_wr = $time;
        time t_e16 = $time - p.gap_ns;            // edge 16 of the previous frame
        check(cfg.en || $time < hold_until, "[scoreboard] frame started while spi_en = 0");
        check(txq.size() != 0, "[scoreboard] frame started with an empty TX FIFO");
        if (txq.size() != 0) begin
          tx_cur.push_back(txq.pop_front());
          t_wr = txq_t.pop_front();
        end
        // byte and spi_en already there when the previous frame ended: back to back
        if (!p.first && busy_n == 0 && cfg.en && t_wr <= t_e16 && t_en_on <= t_e16 &&
            $time - t_e16 < 10 * (p.div + 4) * cfg.clk_ns)
          check(p.gap_ns <= (p.div + 4) * cfg.clk_ns,
                $sformatf("[scoreboard] back-to-back frames: %0d ns from edge 16 to the next edge 1, expected <= %0d ns",
                          p.gap_ns, (p.div + 4) * cfg.clk_ns));
        busy_n++;
      end
      SPI_FRAME: begin
        bit [7:0] exp;
        busy_n--;
        n_frames++;
        if (en_fc) sample_frame_fc(p);
        check(p.half_ok,  $sformatf("[scoreboard] %s: SCLK half period wrong", p.sprint()));
        check(p.setup_ok, $sformatf("[scoreboard] %s: MOSI setup violated", p.sprint()));
        check(p.hold_ok,  $sformatf("[scoreboard] %s: MOSI hold violated", p.sprint()));
        check(p.cs_ok,    $sformatf("[scoreboard] %s: CS changed during the frame", p.sprint()));
        exp = (tx_cur.size() != 0) ? tx_cur.pop_front() : 8'h00;
        check(p.mosi === exp, $sformatf("[scoreboard] MOSI byte %h, model expects %h", p.mosi, exp));
        if (rxq.size() < 16) begin
          rxq.push_back(p.miso);
        end else begin
          rx_ovr = 1'b1;
          n_lost++;
        end
        if (txq.size() == 0) done = 1'b1;
      end
      default: ;
    endcase
  endfunction

  function void report();
    $display("%0t: [scoreboard] %0d transfers, %0d reads compared, %0d frames, %0d RX bytes lost, %0d TX bytes dropped, %0d mismatches",
             $time, n_xfer, n_rd, n_frames, n_lost, n_drop, n_err);
    report_fc();
  endfunction
endclass
