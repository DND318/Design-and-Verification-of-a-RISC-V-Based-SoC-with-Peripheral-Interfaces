// I2C scoreboard (reference model)
class i2c_scoreboard;
  mailbox #(apb_packet) apb_m2s_mb;
  mailbox #(i2c_packet) i2c_m2s_mb;
  i2c_cfg               cfg;

  // reference model
  bit [7:0]        txdata, rxdata;
  bit [1:0]        ier;
  bit              done, nack, rx_nack, bus_busy, bb_known;
  // expected bus events of the command in progress
  i2c_kind_e       exp_kind[$];
  bit              exp_wr[$];      // BYTE: 1 = write (master sends), 0 = read
  bit [7:0]        exp_data[$];    // BYTE write: TXDATA
  bit              exp_nack[$];    // BYTE read: master NACK
  time             t_done;         // command over (done set) by this time
  bit              aborted;        // i2c_en cleared during a command

  // statistics
  int unsigned     n_xfer, n_rd, n_cmd, n_ignored, n_start, n_stop, n_bytes, n_err;
  bit              verbose;
  bit              en_fc = 1'b1;
  `include "coverage.sv"

  function new(mailbox #(apb_packet) apb_m2s_mb, mailbox #(i2c_packet) i2c_m2s_mb, i2c_cfg cfg);
    this.apb_m2s_mb = apb_m2s_mb;
    this.i2c_m2s_mb = i2c_m2s_mb;
    this.cfg        = cfg;
    verbose = $test$plusargs("VERBOSE");
    reset();
`ifndef VERILATOR
    APB_GROUP  = new();   // embedded covergroups are created in the constructor
    CMD_GROUP  = new();
    BYTE_GROUP = new();
    IRQ_GROUP  = new();
`endif
  endfunction

  function void reset();
    cfg.en = 0; cfg.prescale = 124;
    txdata = 0; rxdata = 0; ier = 0;
    done = 0; nack = 0; rx_nack = 0; bus_busy = 0; bb_known = 1;
    exp_kind.delete(); exp_wr.delete(); exp_data.delete(); exp_nack.delete();
    t_done = 0;
    aborted = 0;
  endfunction

  function void check(bit ok, string what);
    if (!ok) n_err++;
    vplan_pkg::chk(ok, what);
  endfunction

  function bit busy();
    return exp_kind.size() != 0 || $time < t_done;
  endfunction

  // No command in progress: STATUS / ISR / RXDATA / irq are stable
  function bit quiet();
    return !busy();
  endfunction

  function bit [1:0] isr();
    return {nack, done};
  endfunction

  task run();
    fork
      apb_run();
      i2c_run();
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

  function void push_exp(i2c_kind_e k, bit wr = 0, bit [7:0] d = 0, bit nk = 0);
    exp_kind.push_back(k);
    exp_wr.push_back(wr);
    exp_data.push_back(d);
    exp_nack.push_back(nk);
  endfunction

  function void command(bit [4:0] c);
    bit s = c[0], p = c[1], w = c[2], r = c[3], nk = c[4];
    if (!cfg.en || busy() || (w && r) || c[3:0] == 4'b0000) begin
      n_ignored++;
      if (verbose) $display("%0t: [scoreboard] CMD %b ignored", $time, c);
      return;
    end
    n_cmd++;
    if (en_fc) sample_cmd_fc(c);
    aborted = 0;
    if (s) push_exp(I2C_START);
    if (w) push_exp(I2C_BYTE, 1'b1, txdata);
    if (r) push_exp(I2C_BYTE, 1'b0, 8'h00, nk);
    if (p) push_exp(I2C_STOP);
  endfunction

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
            $sformatf("[scoreboard] irq_i2c_o = %b, model expects %b (ISR %h, IER %h)",
                      p.irq[0], |(isr() & ier), isr(), ier));
    if (!p.xfer) return;
    n_xfer++;
    if (en_fc) sample_apb_fc(p);
    check(p.pready && !p.pslverr, $sformatf("[scoreboard] %s: PREADY=%b PSLVERR=%b", p.sprint(), p.pready, p.pslverr));
    if (!p.write) begin
      case (p.addr[11:2])
        10'd0: exp = {31'd0, cfg.en};
        10'd1: exp = {16'd0, 16'(cfg.prescale)};
        10'd2: exp = 32'd0;
        10'd3: exp = {24'd0, txdata};
        10'd4: begin
          exp = {24'd0, rxdata};
          cmp = quiet();
        end
        10'd5: begin
          exp = {29'd0, bus_busy, rx_nack, 1'b0};
          cmp = quiet() && bb_known;
        end
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
                            cmp ? "" : " (not compared: command in progress)");
      return;
    end
    if (verbose) $display("%0t: [scoreboard] Get packet from monitor: %s", $time, p.sprint());
    case (p.addr[11:2])
      10'd0: if (p.strb[0]) begin
        if (cfg.en && !p.data[0]) begin
          if (busy()) begin                         // abort
            exp_kind.delete(); exp_wr.delete(); exp_data.delete(); exp_nack.delete();
            t_done  = 0;
            aborted = 1;
          end
          // both lines are released at once: whether the bus monitor of the
          // DUT sees a STOP depends on the line levels (checked by the tests)
          if (bus_busy) bb_known = 0;
        end
        cfg.en = p.data[0];
      end
      10'd1: begin
        if (p.strb[0]) cfg.prescale[7:0]  = p.data[7:0];
        if (p.strb[1]) cfg.prescale[15:8] = p.data[15:8];
      end
      10'd2: if (p.strb[0]) command(p.data[4:0]);
      10'd3: if (p.strb[0]) txdata = p.data[7:0];
      10'd6: if (p.strb[0]) ier = p.data[1:0];
      10'd7: if (p.strb[0]) begin
        if (p.data[0]) done = 1'b0;
        if (p.data[1]) nack = 1'b0;
      end
      default: ;
    endcase
  endfunction

  // ---------------------------------------------------------------- bus side
  task i2c_run();
    i2c_packet p;
    forever begin
      i2c_m2s_mb.get(p);
      if (verbose) $display("%0t: [scoreboard] Get packet from monitor: %s", $time, p.sprint());
      check_bus(p);
    end
  endtask

  function void check_bus(i2c_packet p);
    bit expected = cfg.en && !aborted;
    bit bb_before = bus_busy;
    bit bb_was_known = bb_known;
    if (p.kind == I2C_START) begin n_start++; bus_busy = 1; bb_known = 1; end
    if (p.kind == I2C_STOP)  begin n_stop++;  bus_busy = 0; bb_known = 1; end
    if (p.kind == I2C_BYTE)  n_bytes++;
    if (!expected) return;                         // another device, or an abort
    check(p.t_ok, $sformatf("[scoreboard] %s: bus timing", p.sprint()));
    check(!p.mid_byte, $sformatf("[scoreboard] %s: SDA changed while SCL high inside a byte", p.sprint()));
    if (exp_kind.size() == 0) begin
      check(1'b0, $sformatf("[scoreboard] %s: no command in progress", p.sprint()));
      return;
    end
    check(p.kind == exp_kind[0], $sformatf("[scoreboard] %s: model expects %s", p.sprint(), exp_kind[0].name()));
    if (p.kind == I2C_BYTE && exp_kind[0] == I2C_BYTE) begin
      if (en_fc) sample_byte_fc(exp_wr[0], p.ack);
      if (exp_wr[0]) begin                         // write
        check(p.data === exp_data[0], $sformatf("[scoreboard] byte %h on the bus, model expects TXDATA %h", p.data, exp_data[0]));
        check(p.s_low == 8'h00, "[scoreboard] write: the slave pulled SDA low in a data bit");
        check(p.m_low == ~p.data, $sformatf("[scoreboard] write: master SDA pulls %h, data %h", p.m_low, p.data));
        check(!p.m_ack, "[scoreboard] write: the master pulled SDA low in the ACK bit");
        rx_nack = p.ack;
        if (p.ack) nack = 1'b1;
      end else begin                               // read
        check(p.m_low == 8'h00, "[scoreboard] read: the master pulled SDA low in a data bit");
        check(p.ack == exp_nack[0], $sformatf("[scoreboard] read: master %s, CMD.nack = %b",
                                              p.ack ? "NACK" : "ACK", exp_nack[0]));
        check(p.m_ack == !exp_nack[0] && !p.s_ack, $sformatf("[scoreboard] read: ACK bit driven by master %b / slave %b, CMD.nack = %b",
                                                            p.m_ack, p.s_ack, exp_nack[0]));
        rxdata = p.data;
      end
    end
    if (p.kind == I2C_START && exp_kind[0] == I2C_START)
      if (bb_was_known)
        check(p.rs == bb_before, $sformatf("[scoreboard] %s: model bus_busy before it = %b", p.sprint(), bb_before));
    void'(exp_kind.pop_front()); void'(exp_wr.pop_front()); void'(exp_data.pop_front()); void'(exp_nack.pop_front());
    if (exp_kind.size() == 0) begin                // last event: command done a little later
      done   = 1'b1;
      t_done = $time + 2 * cfg.q_ns() + 4 * cfg.clk_ns;
    end
  endfunction

  // The test gave up waiting for the rest of a command: forget it, ignore
  // the bus until the next command
  function void drop_cmd();
    exp_kind.delete(); exp_wr.delete(); exp_data.delete(); exp_nack.delete();
    t_done   = 0;
    aborted  = 1;
    bb_known = 0;
  endfunction

  function void report();
    $display("%0t: [scoreboard] %0d transfers, %0d reads compared, %0d commands (%0d ignored), %0d START, %0d STOP, %0d bytes, %0d mismatches",
             $time, n_xfer, n_rd, n_cmd, n_ignored, n_start, n_stop, n_bytes, n_err);
    report_fc();
  endfunction
endclass
