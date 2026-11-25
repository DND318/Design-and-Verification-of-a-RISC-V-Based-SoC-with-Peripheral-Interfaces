// Bus driver: CPU memory ports and direct AXI port
class bus_driver;
  mailbox #(bus_packet) s2d_mb;
  mailbox #(bus_packet) d2s_mb;
  virtual cpu_if        cpu_vif[2];
  virtual axi_if        axd_vif;      // direct AXI port
  int unsigned          n_ready[2];

  function new(virtual cpu_if cpu0, virtual cpu_if cpu1, virtual axi_if axd_vif,
               mailbox #(bus_packet) s2d_mb, mailbox #(bus_packet) d2s_mb);
    cpu_vif[0]   = cpu0;
    cpu_vif[1]   = cpu1;
    this.axd_vif = axd_vif;
    this.s2d_mb  = s2d_mb;
    this.d2s_mb  = d2s_mb;
  endfunction

  task run();
    bus_packet pkt;
    foreach (cpu_vif[p]) begin
      cpu_vif[p].req = 1'b0; cpu_vif[p].instr = 1'b0; cpu_vif[p].we = 1'b0;
      cpu_vif[p].wstrb = 4'h0; cpu_vif[p].addr = 32'h0; cpu_vif[p].wdata = 32'h0;
      cpu_vif[p].direct = 1'b0;
    end
    axd_vif.awvalid = 1'b0; axd_vif.wvalid = 1'b0; axd_vif.arvalid = 1'b0;
    axd_vif.bready = 1'b0;  axd_vif.rready = 1'b0;
    axd_vif.awaddr = 32'h0; axd_vif.wdata = 32'h0; axd_vif.wstrb = 4'h0; axd_vif.araddr = 32'h0;
    axd_vif.awprot = 3'b001; axd_vif.arprot = 3'b001;
    fork
      count_ready(0);
      count_ready(1);
    join_none
    while (1) begin
      s2d_mb.get(pkt);
      if ($test$plusargs("VERBOSE")) $display("%0t: [bus_driver] Get packet from stimulus: %s", $time, pkt.sprint());
      if (pkt.kind == BUS_AXI) axi_direct(pkt);
      else                     cpu_req(pkt);
      d2s_mb.put(pkt);                           // done
    end
  endtask

  task count_ready(input int p);
    while (1) begin
      @(posedge cpu_vif[p].clk);
      if (cpu_vif[p].rst_n === 1'b1 && cpu_vif[p].ready === 1'b1) begin
        n_ready[p]++;
        vplan_pkg::chk_at("BUS-15", cpu_vif[p].req === 1'b1,
                          $sformatf("[bus_driver] CPU port %0d: mem_ready without a request", p));
      end
    end
  endtask

  task cpu_req(bus_packet pkt);
    int unsigned n0, cyc;
    int          p = pkt.port;
    if (cpu_vif[p].req !== 1'b1) begin
      @(posedge cpu_vif[p].clk);
      #1;
    end
    n0  = n_ready[p];
    cyc = 0;
    cpu_vif[p].req   = 1'b1;
    cpu_vif[p].we    = pkt.we;
    cpu_vif[p].instr = pkt.instr;
    cpu_vif[p].addr  = pkt.addr;
    cpu_vif[p].wdata = pkt.wdata;
    cpu_vif[p].wstrb = pkt.we ? pkt.wstrb : 4'h0;
    do begin
      @(negedge cpu_vif[p].clk);
      cyc++;
    end while (cpu_vif[p].ready !== 1'b1 && cyc < 500);
    pkt.rdata = cpu_vif[p].rdata;
    pkt.err   = cpu_vif[p].err;
    @(posedge cpu_vif[p].clk);
    #1;
    pkt.n_ready = n_ready[p] - n0;
    if (!pkt.keep) begin
      cpu_vif[p].req = 1'b0; cpu_vif[p].we = 1'b0; cpu_vif[p].instr = 1'b0; cpu_vif[p].wstrb = 4'h0;
    end
  endtask

  // Write (AW + W) and / or read (AR) valid in the same cycle on the xbar input
  task axi_direct(bus_packet pkt);
    cpu_vif[0].direct = 1'b1;
    @(posedge axd_vif.clk);
    #1;
    axd_vif.awaddr = pkt.addr;  axd_vif.awvalid = pkt.do_wr;
    axd_vif.wdata  = pkt.wdata; axd_vif.wstrb = pkt.wstrb; axd_vif.wvalid = pkt.do_wr;
    axd_vif.araddr = pkt.raddr; axd_vif.arvalid = pkt.do_rd;
    axd_vif.bready = 1'b1;      axd_vif.rready = 1'b1;
    fork
      if (pkt.do_wr) begin
        do @(posedge axd_vif.clk); while (axd_vif.awready !== 1'b1);
        #1 axd_vif.awvalid = 1'b0;
      end
      if (pkt.do_wr) begin
        do @(posedge axd_vif.clk); while (axd_vif.wready !== 1'b1);
        #1 axd_vif.wvalid = 1'b0;
      end
      if (pkt.do_rd) begin
        do @(posedge axd_vif.clk); while (axd_vif.arready !== 1'b1);
        #1 axd_vif.arvalid = 1'b0;
      end
      if (pkt.do_wr) begin
        do @(posedge axd_vif.clk); while (axd_vif.bvalid !== 1'b1);
        pkt.bresp = axd_vif.bresp;
      end
      if (pkt.do_rd) begin
        do @(posedge axd_vif.clk); while (axd_vif.rvalid !== 1'b1);
        pkt.rresp = axd_vif.rresp;
        pkt.rdata = axd_vif.rdata;
      end
    join
    @(posedge axd_vif.clk);
    #1;
    axd_vif.bready = 1'b0; axd_vif.rready = 1'b0;
    cpu_vif[0].direct = 1'b0;
  endtask
endclass
