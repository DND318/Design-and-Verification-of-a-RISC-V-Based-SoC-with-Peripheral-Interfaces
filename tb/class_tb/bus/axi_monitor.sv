// AXI4-Lite monitor
class axi_monitor;
  virtual axi_if        dut_vif;
  mailbox #(bus_packet) m2s_mb;
  int                   port;
  bit                   chk_valid;
  int                   rep_dly;
  string                tag;

  function new(virtual axi_if dut_vif, mailbox #(bus_packet) m2s_mb, int port, bit chk_valid, int rep_dly);
    this.dut_vif   = dut_vif;
    this.m2s_mb    = m2s_mb;
    this.port      = port;
    this.chk_valid = chk_valid;
    this.rep_dly   = rep_dly;
    tag = $sformatf("axi_monitor %0d", port);
  endfunction

  task run();
    bus_packet   wq[$], rq[$], p;
    bit [31:0]   awaddr, wdata, araddr;
    bit [3:0]    wstrb;
    bit [2:0]    awprot, arprot;
    bit          aw_ok, w_ok;
    bit          p_awv, p_awr, p_wv, p_wr, p_arv, p_arr;
    bit [31:0]   p_awaddr, p_wdata, p_araddr;
    bit [3:0]    p_wstrb;
    int          rd_pend, ar_cyc[$];
    longint unsigned cyc;
    while (1) begin
      @(negedge dut_vif.clk);
      cyc++;
      if (dut_vif.rst_n !== 1'b1) begin
        aw_ok = 0; w_ok = 0; rd_pend = 0; ar_cyc.delete();
        p_awv = 0; p_wv = 0; p_arv = 0;
        continue;
      end
      // BUS-14: VALID and payload held until READY
      if (chk_valid) begin
        if (p_awv && !p_awr)
          vplan_pkg::chk_at("BUS-14", dut_vif.awvalid === 1'b1 && dut_vif.awaddr == p_awaddr,
                            $sformatf("[%s] AWVALID / AWADDR changed before AWREADY", tag));
        if (p_wv && !p_wr)
          vplan_pkg::chk_at("BUS-14", dut_vif.wvalid === 1'b1 && dut_vif.wdata == p_wdata && dut_vif.wstrb == p_wstrb,
                            $sformatf("[%s] WVALID / WDATA / WSTRB changed before WREADY", tag));
        if (p_arv && !p_arr)
          vplan_pkg::chk_at("BUS-14", dut_vif.arvalid === 1'b1 && dut_vif.araddr == p_araddr,
                            $sformatf("[%s] ARVALID / ARADDR changed before ARREADY", tag));
      end
      p_awv = dut_vif.awvalid; p_awr = dut_vif.awready; p_awaddr = dut_vif.awaddr;
      p_wv  = dut_vif.wvalid;  p_wr  = dut_vif.wready;  p_wdata  = dut_vif.wdata; p_wstrb = dut_vif.wstrb;
      p_arv = dut_vif.arvalid; p_arr = dut_vif.arready; p_araddr = dut_vif.araddr;

      if (port == 1 && dut_vif.rvalid === 1'b1)
        vplan_pkg::chk_at("BUS-07", rd_pend > 0, $sformatf("[%s] SRAM RVALID without an earlier AR handshake", tag));

      if (dut_vif.awvalid && dut_vif.awready) begin
        aw_ok = 1; awaddr = dut_vif.awaddr; awprot = dut_vif.awprot;
      end
      if (dut_vif.wvalid && dut_vif.wready) begin
        w_ok = 1; wdata = dut_vif.wdata; wstrb = dut_vif.wstrb;
      end
      if (dut_vif.arvalid && dut_vif.arready) begin
        araddr = dut_vif.araddr; arprot = dut_vif.arprot;
        rd_pend++;
        ar_cyc.push_back(cyc);
      end
      if (dut_vif.bvalid && dut_vif.bready) begin
        p = new();
        p.kind = BUS_AXI_WR; p.port = port; p.we = 1;
        p.addr = awaddr; p.prot = awprot; p.wdata = wdata; p.wstrb = wstrb;
        p.resp = dut_vif.bresp; p.direct = (dut_vif.direct === 1'b1); p.cyc = cyc;
        if (!(aw_ok && w_ok))
          vplan_pkg::chk(1'b0, $sformatf("[%s] BVALID before the AW and W handshakes", tag));
        aw_ok = 0; w_ok = 0;
        wq.push_back(p);
      end
      if (dut_vif.rvalid && dut_vif.rready) begin
        p = new();
        p.kind = BUS_AXI_RD; p.port = port; p.we = 0;
        p.addr = araddr; p.prot = arprot; p.rdata = dut_vif.rdata;
        p.resp = dut_vif.rresp; p.direct = (dut_vif.direct === 1'b1);
        p.cyc = (ar_cyc.size() != 0) ? cyc - ar_cyc.pop_front() : 0;   // AR handshake to R handshake
        if (rd_pend > 0) rd_pend--;
        rq.push_back(p);
      end
      if (wq.size() + rq.size() != 0) begin
        if (rep_dly != 0) #(rep_dly * 1ns);
        while (wq.size() != 0) begin
          p = wq.pop_front();
          if ($test$plusargs("VERBOSE")) $display("%0t: [%s] %s", $time, tag, p.sprint());
          m2s_mb.put(p);
        end
        while (rq.size() != 0) begin
          p = rq.pop_front();
          if ($test$plusargs("VERBOSE")) $display("%0t: [%s] %s", $time, tag, p.sprint());
          m2s_mb.put(p);
        end
      end
    end
  endtask
endclass
