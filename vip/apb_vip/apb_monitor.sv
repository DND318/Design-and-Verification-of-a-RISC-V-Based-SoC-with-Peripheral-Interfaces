// Monitor: watches the APB pins and the irq outputs through the virtual
// interface and sends one packet to the scoreboard (m2s_mb) for each rising
// edge at which a transfer completes, reset is active or an irq output
// changes. Values are sampled at the edge, before the DUT updates its flops.
// flush_req forces one packet at the next edge, so the scoreboard catches up
// before the test moves on to the next vplan item.
class apb_monitor;
  virtual apb_if        vif;
  mailbox #(apb_packet) m2s_mb;
  longint unsigned      edge_no;
  bit                   flush_req;
  bit                   verbose;

  function new(virtual apb_if vif, mailbox #(apb_packet) m2s_mb);
    this.vif    = vif;
    this.m2s_mb = m2s_mb;
    verbose = $test$plusargs("VERBOSE");
  endfunction

  task run();
    apb_packet p;
    bit [7:0]  irq_last = 8'h00;
    bit        xfer;
    forever begin
      @(posedge vif.clk);
      edge_no++;
      xfer = (vif.rst_n === 1'b1) && (vif.psel === 1'b1) && (vif.penable === 1'b1) &&
             (vif.pready !== 1'b0);
      if (vif.rst_n !== 1'b1 || xfer || vif.irq !== irq_last || flush_req) begin
        p = new();
        p.edge_no = edge_no;
        p.rst_n   = (vif.rst_n === 1'b1);
        p.xfer    = xfer;
        p.write   = vif.pwrite;
        p.addr    = vif.paddr;
        p.data    = vif.pwdata;
        p.strb    = vif.pstrb;
        p.rdata   = vif.prdata;
        p.pready  = (vif.pready === 1'b1);
        p.pslverr = (vif.pslverr !== 1'b0);
        p.irq     = vif.irq;
        if (verbose && xfer) $display("%0t: [monitor] %s", $time, p.sprint());
        if (verbose && vif.irq !== irq_last) $display("%0t: [monitor] irq %b -> %b", $time, irq_last, vif.irq);
        m2s_mb.put(p);
        flush_req = 1'b0;
      end
      irq_last = vif.irq;
    end
  endtask
endclass
