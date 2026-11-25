// GPIO monitor
class gpio_monitor;
  virtual gpio_if        dut_vif;
  mailbox #(gpio_packet) m2s_mb;
  longint unsigned       edge_no;      // rising edges since time 0

  function new(virtual gpio_if dut_vif, mailbox #(gpio_packet) m2s_mb);
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
    gpio_packet pkt;
    gpio_packet last = new();
    while (1) begin
      @(negedge dut_vif.clk);
      pkt = new();
      pkt.edge_no = edge_no;
      pkt.rst_n   = (dut_vif.rst_n === 1'b1);
      pkt.gpio_i  = dut_vif.gpio_i;
      pkt.gpio_o  = dut_vif.gpio_o;
      pkt.gpio_oe = dut_vif.gpio_oe;
      pkt.irq     = dut_vif.irq;
      if (pkt.gpio_i != last.gpio_i || pkt.gpio_o != last.gpio_o || pkt.gpio_oe != last.gpio_oe ||
          pkt.irq != last.irq)
        $display("%0t: [gpio_monitor] %s", $time, pkt.sprint());
      last = pkt;
      m2s_mb.put(pkt);
    end
  endtask
endclass
