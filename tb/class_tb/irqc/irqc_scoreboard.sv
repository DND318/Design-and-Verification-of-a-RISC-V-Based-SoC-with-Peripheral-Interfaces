// IRQC scoreboard (reference model)
class irqc_scoreboard;
  mailbox #(apb_packet)  apb_m2s_mb;
  mailbox #(irqc_packet) irqc_m2s_mb;

  bit [3:0]        en_r;                // IRQ_ENABLE
  bit [3:0]        lines_at_edge;       // lines as the DUT sees them at the next edge
  int unsigned     n_xfer, n_rd, n_edges, n_err;
  bit              verbose;
  bit              en_fc = 1'b1;
  `include "coverage.sv"

  function new(mailbox #(apb_packet) apb_m2s_mb, mailbox #(irqc_packet) irqc_m2s_mb);
    this.apb_m2s_mb  = apb_m2s_mb;
    this.irqc_m2s_mb = irqc_m2s_mb;
    verbose = $test$plusargs("VERBOSE");
`ifndef VERILATOR
    APB_GROUP = new();   // embedded covergroups are created in the constructor
    IRQ_GROUP = new();
`endif
  endfunction

  function void check(bit ok, string what);
    if (!ok) n_err++;
    vplan_pkg::chk(ok, what);
  endfunction

  static function bit [2:0] irq_id(bit [3:0] st);
    for (int i = 0; i < 4; i++) if (st[i]) return 3'(i + 1);
    return 3'd0;
  endfunction

  function bit [31:0] read(bit [11:0] addr, bit [3:0] lines);
    case (addr[11:2])
      10'd0:   return {28'd0, lines};
      10'd1:   return {28'd0, en_r};
      10'd2:   return {28'd0, lines & en_r};
      10'd3:   return {29'd0, irq_id(lines & en_r)};
      default: return 32'd0;
    endcase
  endfunction

  task run();
    irqc_packet g;
    apb_packet  a;
    bit         have_a;
    while (1) begin
      irqc_m2s_mb.get(g);
      n_edges++;
      have_a = 1'b0;
      while (apb_m2s_mb.try_peek(a) && a.edge_no <= g.edge_no) begin
        void'(apb_m2s_mb.try_get(a));
        if (a.edge_no == g.edge_no) have_a = 1'b1;
      end
      if (!g.rst_n) begin
        en_r = 4'h0;
        lines_at_edge = g.irq_in;
        continue;
      end
      if (have_a && a.xfer && a.rst_n) begin
        n_xfer++;
        if (en_fc) sample_apb_fc(a);
        check(a.pready && !a.pslverr, $sformatf("[scoreboard] %s: PREADY=%b PSLVERR=%b", a.sprint(), a.pready, a.pslverr));
        if (!a.write) begin
          n_rd++;
          check(a.rdata === read(a.addr, lines_at_edge),
                $sformatf("[scoreboard] read %h = %h, model expects %h (lines %b, ENABLE %b)",
                          a.addr, a.rdata, read(a.addr, lines_at_edge), lines_at_edge, en_r));
        end else if (a.strb[0] && a.addr[11:2] == 10'd1) begin
          en_r = a.data[3:0];
        end
        if (verbose) $display("%0t: [scoreboard] Get packet from monitor: %s", $time, a.sprint());
      end
      check(g.irq === |(g.irq_in & en_r),
            $sformatf("[scoreboard] edge %0d: irq_meip_o=%b, model expects %b (lines %b, ENABLE %b)",
                      g.edge_no, g.irq, |(g.irq_in & en_r), g.irq_in, en_r));
      if (en_fc) sample_irq_fc(g.irq_in, en_r);
      lines_at_edge = g.irq_in;
    end
  endtask

  function void report();
    $display("%0t: [scoreboard] %0d transfers, %0d reads compared, %0d clocks compared, %0d mismatches",
             $time, n_xfer, n_rd, n_edges, n_err);
    report_fc();
  endfunction
endclass
