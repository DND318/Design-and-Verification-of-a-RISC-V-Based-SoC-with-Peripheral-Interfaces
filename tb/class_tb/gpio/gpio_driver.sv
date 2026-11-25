// GPIO driver: drives the gpio_i pins
class gpio_driver;
  mailbox #(gpio_packet) s2d_mb;
  mailbox #(gpio_packet) d2s_mb;
  virtual gpio_if        dut_vif;

  function new(virtual gpio_if dut_vif, mailbox #(gpio_packet) s2d_mb, mailbox #(gpio_packet) d2s_mb);
    this.dut_vif = dut_vif;
    this.s2d_mb  = s2d_mb;
    this.d2s_mb  = d2s_mb;
  endfunction

  task run();
    gpio_packet pkt;
    dut_vif.gpio_i = 8'h00;

    while (1) begin
      s2d_mb.get(pkt);
      $display("%0t: [gpio_driver] Get packet from stimulus: gpio_i=%h for %0d clocks", $time, pkt.data, pkt.hold);
      @(posedge dut_vif.clk);
      #3;
      dut_vif.gpio_i = pkt.data;
      if (pkt.hold > 1) repeat (pkt.hold - 1) @(posedge dut_vif.clk);
      d2s_mb.put(pkt);                           // done
    end
  endtask
endclass
