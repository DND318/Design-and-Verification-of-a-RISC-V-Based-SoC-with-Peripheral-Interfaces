// CPU memory port monitor
class cpu_monitor;
  virtual cpu_if        dut_vif;
  mailbox #(bus_packet) m2s_mb;
  int                   port;

  function new(virtual cpu_if dut_vif, mailbox #(bus_packet) m2s_mb, int port);
    this.dut_vif = dut_vif;
    this.m2s_mb  = m2s_mb;
    this.port    = port;
  endfunction

  task run();
    bus_packet p;
    while (1) begin
      @(negedge dut_vif.clk);
      if (dut_vif.rst_n !== 1'b1 || dut_vif.ready !== 1'b1) continue;
      p = new();
      p.kind  = BUS_CPU;
      p.port  = port;
      p.we    = dut_vif.we;
      p.instr = dut_vif.instr;
      p.addr  = dut_vif.addr;
      p.wdata = dut_vif.wdata;
      p.wstrb = dut_vif.wstrb;
      p.rdata = dut_vif.rdata;
      p.err   = dut_vif.err;
      #3ns;
      if ($test$plusargs("VERBOSE")) $display("%0t: [cpu_monitor %0d] %s -> %h err %b", $time, port, p.sprint(), p.rdata, p.err);
      m2s_mb.put(p);
    end
  endtask
endclass
