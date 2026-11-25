// AXI4-Lite slave model with random delays
class axi_slave;
  virtual axi_if dut_vif;
  bit [1:0]      resp = 2'b00;
  bit [31:0]     last_awaddr, last_wdata, last_araddr;
  bit [3:0]      last_wstrb;
  bit [2:0]      last_awprot, last_arprot;
  int            aw_d, w_d, ar_d, b_d, r_d;
  bit            aw_got, w_got, ar_got;

  function new(virtual axi_if dut_vif);
    this.dut_vif = dut_vif;
  endfunction

  task run();
    bit hs_aw, hs_w, hs_b, hs_ar, hs_r;
    dut_vif.awready = 0; dut_vif.wready = 0; dut_vif.arready = 0;
    dut_vif.bvalid = 0;  dut_vif.rvalid = 0;
    dut_vif.bresp = 0;   dut_vif.rresp = 0;  dut_vif.rdata = 0;
    while (1) begin
      @(negedge dut_vif.clk);
      if (dut_vif.rst_n !== 1'b1) begin
        aw_got = 0; w_got = 0; ar_got = 0;
        dut_vif.awready = 0; dut_vif.wready = 0; dut_vif.arready = 0;
        dut_vif.bvalid = 0;  dut_vif.rvalid = 0;
        continue;
      end
      hs_aw = dut_vif.awvalid && dut_vif.awready;
      hs_w  = dut_vif.wvalid  && dut_vif.wready;
      hs_b  = dut_vif.bvalid  && dut_vif.bready;
      hs_ar = dut_vif.arvalid && dut_vif.arready;
      hs_r  = dut_vif.rvalid  && dut_vif.rready;
      if (hs_aw) begin aw_got = 1; last_awaddr = dut_vif.awaddr; last_awprot = dut_vif.awprot; end
      if (hs_w)  begin w_got = 1;  last_wdata = dut_vif.wdata;   last_wstrb = dut_vif.wstrb; end
      if (hs_ar) begin ar_got = 1; last_araddr = dut_vif.araddr; last_arprot = dut_vif.arprot; end
      @(posedge dut_vif.clk);
      #1;
      // AW
      if (hs_aw) begin
        dut_vif.awready = 0;
        aw_d = $urandom_range(3);
      end else if (dut_vif.awvalid && !aw_got && !dut_vif.awready) begin
        if (aw_d == 0) dut_vif.awready = 1; else aw_d--;
      end
      // W
      if (hs_w) begin
        dut_vif.wready = 0;
        w_d = $urandom_range(3);
      end else if (dut_vif.wvalid && !w_got && !dut_vif.wready) begin
        if (w_d == 0) dut_vif.wready = 1; else w_d--;
      end
      // B
      if (hs_b) begin
        dut_vif.bvalid = 0;
        aw_got = 0; w_got = 0;
        b_d = $urandom_range(3);
      end else if (aw_got && w_got && !dut_vif.bvalid) begin
        if (b_d == 0) begin dut_vif.bvalid = 1; dut_vif.bresp = resp; end else b_d--;
      end
      // AR
      if (hs_ar) begin
        dut_vif.arready = 0;
        ar_d = $urandom_range(3);
      end else if (dut_vif.arvalid && !ar_got && !dut_vif.arready) begin
        if (ar_d == 0) dut_vif.arready = 1; else ar_d--;
      end
      // R
      if (hs_r) begin
        dut_vif.rvalid = 0;
        ar_got = 0;
        r_d = $urandom_range(3);
      end else if (ar_got && !dut_vif.rvalid) begin
        if (r_d == 0) begin
          dut_vif.rvalid = 1; dut_vif.rresp = resp; dut_vif.rdata = ~last_araddr;
        end else r_d--;
      end
    end
  endtask
endclass
