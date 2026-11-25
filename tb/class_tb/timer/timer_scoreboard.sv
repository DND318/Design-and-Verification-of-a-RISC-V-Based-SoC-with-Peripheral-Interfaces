// Timer scoreboard (reference model)
class timer_scoreboard;
  mailbox #(apb_packet) m2s_mb;
  timer_model           model;
  longint unsigned      m_edge;      // model state = state after edge m_edge
  bit                   obs_irq;     // irq level seen at the last reported edge
  int unsigned          n_xfer, n_rd, n_irq_chg, n_err;
  bit                   verbose;

  bit                   en_fc = 1'b1;
  `include "coverage.sv"

  function new(mailbox #(apb_packet) m2s_mb);
    this.m2s_mb = m2s_mb;
    model = new();
    verbose = $test$plusargs("VERBOSE");
`ifndef VERILATOR
    APB_GROUP = new();   // embedded covergroups are created in the constructor
    CFG_GROUP = new();
    IRQ_GROUP = new();
`endif
  endfunction

  function void check(bit ok, string what);
    if (!ok) n_err++;
    vplan_pkg::chk(ok, what);
  endfunction

  task run();
    apb_packet p;
    forever begin
      m2s_mb.get(p);
      check_packet(p);
    end
  endtask

  function void check_packet(apb_packet p);
    bit [31:0] exp;
    int unsigned bad = 0;
    longint unsigned first_bad = 0;
    // reset (asynchronous): the edge shows the reset state
    if (!p.rst_n) begin
      model.reset();
      m_edge  = p.edge_no;
      if (p.irq[0] !== 1'b0) check(1'b0, "[scoreboard] irq_mtip High during reset");
      obs_irq = 1'b0;
      return;
    end
    // edges with nothing to report: the irq level must have matched the model
    while (m_edge + 1 < p.edge_no) begin
      if (model.irq != obs_irq) begin
        if (bad == 0) first_bad = m_edge + 1;
        bad++;
      end
      model.step(1'b0, 12'h0, 32'h0, 4'h0);
      m_edge++;
    end
    if (bad != 0)
      check(1'b0, $sformatf("[scoreboard] irq_mtip = %b for %0d edges from edge %0d, model expects %b",
                            obs_irq, bad, first_bad, !obs_irq));
    // this edge shows the state after edge p.edge_no - 1
    if (p.irq[0] != obs_irq) n_irq_chg++;
    if (model.irq != p.irq[0])
      check(1'b0, $sformatf("[scoreboard] irq_mtip = %b at edge %0d, model expects %b",
                            p.irq[0], p.edge_no, model.irq));
    obs_irq = p.irq[0];
    if (p.xfer) begin
      n_xfer++;
      check(p.pready && !p.pslverr, $sformatf("[scoreboard] %s: PREADY=%b PSLVERR=%b",
                                             p.sprint(), p.pready, p.pslverr));
      if (!p.write) begin
        n_rd++;
        exp = model.read(p.addr);
        check(p.rdata === exp, $sformatf("[scoreboard] read %h = %h, model expects %h",
                                         p.addr, p.rdata, exp));
      end
      if (verbose) $display("%0t: [scoreboard] %s checked", $time, p.sprint());
    end
    if (en_fc) begin
      if (p.xfer) sample_apb_fc(p);
      sample_irq_fc(model);
    end
    model.step(p.xfer && p.write, p.addr, p.data, p.strb);
    m_edge = p.edge_no;
  endfunction

  function void report();
    $display("%0t: [scoreboard] %0d transfers, %0d reads compared with the model, %0d irq changes, %0d mismatches",
             $time, n_xfer, n_rd, n_irq_chg, n_err);
    report_fc();
  endfunction
endclass
