// IRQC driver: drives the interrupt lines
class irqc_driver;
  mailbox #(irqc_packet) s2d_mb;
  mailbox #(irqc_packet) d2s_mb;
  virtual irqc_if        dut_vif;

  function new(virtual irqc_if dut_vif, mailbox #(irqc_packet) s2d_mb, mailbox #(irqc_packet) d2s_mb);
    this.dut_vif = dut_vif;
    this.s2d_mb  = s2d_mb;
    this.d2s_mb  = d2s_mb;
  endfunction

  task run();
    irqc_packet pkt;
    dut_vif.irq_in = 4'h0;

    while (1) begin
      s2d_mb.get(pkt);
      $display("%0t: [irqc_driver] Get packet from stimulus: lines=%b for %0d clocks", $time, pkt.data, pkt.hold);
      @(posedge dut_vif.clk);
      #3;
      dut_vif.irq_in = pkt.data;
      if (pkt.hold > 1) repeat (pkt.hold - 1) @(posedge dut_vif.clk);
      d2s_mb.put(pkt);                           // done
    end
  endtask
endclass
