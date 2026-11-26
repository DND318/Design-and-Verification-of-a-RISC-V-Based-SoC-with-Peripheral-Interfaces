// IRQC monitor
class irqc_monitor;
  virtual irqc_if        dut_vif;
  mailbox #(irqc_packet) m2s_mb;
  longint unsigned       edge_no;      // rising edges since time 0

  function new(virtual irqc_if dut_vif, mailbox #(irqc_packet) m2s_mb);
    this.dut_vif = dut_vif;
    this.m2s_mb  = m2s_mb;
  endfunction

  task run();
    fork
      count_edges();
      sample();
    join
  endtask

  task count_edges();
    while (1) begin
      @(posedge dut_vif.clk);
      edge_no++;
    end
  endtask

  task sample();
    irqc_packet pkt;
    irqc_packet last = new();
    while (1) begin
      @(negedge dut_vif.clk);
      pkt = new();
      pkt.edge_no = edge_no;
      pkt.rst_n   = (dut_vif.rst_n === 1'b1);
      pkt.irq_in  = dut_vif.irq_in;
      pkt.irq     = dut_vif.irq;
      if (pkt.irq_in != last.irq_in || pkt.irq != last.irq)
        $display("%0t: [irqc_monitor] %s", $time, pkt.sprint());
      last = pkt;
      m2s_mb.put(pkt);
    end
  endtask
endclass
