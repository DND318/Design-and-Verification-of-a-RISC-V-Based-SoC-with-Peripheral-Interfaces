// Bus testbench top (make tests TOP=bus)
`timescale 1ns/1ps
module testbench;
  import bus_pkg::*;
  import test_pkg::*;

  // $readmemh paths are relative to the simulator's working directory:
  // sim/ for Verilator, sim/work/ for XSim.
`ifdef VERILATOR
  localparam TV = "../tb/test_vectors/";
`else
  localparam TV = "../../tb/test_vectors/";
`endif
  localparam INIT_B0 = {TV, "bus_init_b0.hex"};
  localparam INIT_B1 = {TV, "bus_init_b1.hex"};
  localparam INIT_B2 = {TV, "bus_init_b2.hex"};
  localparam INIT_B3 = {TV, "bus_init_b3.hex"};

  logic clk;
  logic rst_n;

  cpu_if  cpu_if_0 (clk);
  cpu_if  cpu_if_1 (clk);
  axi_if  axi_direct (clk);      // driven by bus_driver in direct mode
  axi_if  axi_if_0 (clk);        // xbar input (watched)
  axi_if  axi_if_1 (clk);        // SRAM port of the xbar (watched)
  axi_if  axi_if_2 (clk);        // second master <-> axi_slave
  apbm_if apb_if_0 (clk);

  // ---------------------------------------------------------------- main path
  wire [31:0] mem_rdata;
  wire        mem_ready, mem_err;
  wire [31:0] ma_awaddr, ma_wdata, ma_araddr;
  wire [2:0]  ma_awprot, ma_arprot;
  wire [3:0]  ma_wstrb;
  wire        ma_awvalid, ma_wvalid, ma_bready, ma_arvalid, ma_rready;

  wire        direct = (cpu_if_0.direct === 1'b1);
  wire [31:0] x_awaddr  = direct ? axi_direct.awaddr  : ma_awaddr;
  wire [2:0]  x_awprot  = direct ? axi_direct.awprot  : ma_awprot;
  wire        x_awvalid = direct ? axi_direct.awvalid : ma_awvalid;
  wire [31:0] x_wdata   = direct ? axi_direct.wdata   : ma_wdata;
  wire [3:0]  x_wstrb   = direct ? axi_direct.wstrb   : ma_wstrb;
  wire        x_wvalid  = direct ? axi_direct.wvalid  : ma_wvalid;
  wire        x_bready  = direct ? axi_direct.bready  : ma_bready;
  wire [31:0] x_araddr  = direct ? axi_direct.araddr  : ma_araddr;
  wire [2:0]  x_arprot  = direct ? axi_direct.arprot  : ma_arprot;
  wire        x_arvalid = direct ? axi_direct.arvalid : ma_arvalid;
  wire        x_rready  = direct ? axi_direct.rready  : ma_rready;
  wire        x_awready, x_wready, x_bvalid, x_arready, x_rvalid;
  wire [1:0]  x_bresp, x_rresp;
  wire [31:0] x_rdata;

  wire [31:0] m0_awaddr, m0_wdata, m0_araddr, m0_rdata;
  wire [2:0]  m0_awprot, m0_arprot;
  wire [3:0]  m0_wstrb;
  wire        m0_awvalid, m0_awready, m0_wvalid, m0_wready, m0_bvalid, m0_bready;
  wire        m0_arvalid, m0_arready, m0_rvalid, m0_rready;
  wire [1:0]  m0_bresp, m0_rresp;
  wire [31:0] m1_awaddr, m1_wdata, m1_araddr, m1_rdata;
  wire [2:0]  m1_awprot, m1_arprot;
  wire [3:0]  m1_wstrb;
  wire        m1_awvalid, m1_awready, m1_wvalid, m1_wready, m1_bvalid, m1_bready;
  wire        m1_arvalid, m1_arready, m1_rvalid, m1_rready;
  wire [1:0]  m1_bresp, m1_rresp;

  wire [15:0] psel;
  wire        penable, pwrite;
  wire [11:0] paddr;
  wire [31:0] pwdata;
  wire [3:0]  pstrb;
  wire [2:0]  pprot;

  axi_lite_master u_mst (
    .clk_i(clk), .rst_ni(rst_n),
    .mem_req_i(cpu_if_0.req), .mem_instr_i(cpu_if_0.instr), .mem_we_i(cpu_if_0.we), .mem_wstrb_i(cpu_if_0.wstrb),
    .mem_addr_i(cpu_if_0.addr), .mem_wdata_i(cpu_if_0.wdata), .mem_rdata_o(mem_rdata),
    .mem_ready_o(mem_ready), .mem_err_o(mem_err),
    .m_awaddr_o(ma_awaddr), .m_awprot_o(ma_awprot), .m_awvalid_o(ma_awvalid), .m_awready_i(x_awready && !direct),
    .m_wdata_o(ma_wdata), .m_wstrb_o(ma_wstrb), .m_wvalid_o(ma_wvalid), .m_wready_i(x_wready && !direct),
    .m_bresp_i(x_bresp), .m_bvalid_i(x_bvalid && !direct), .m_bready_o(ma_bready),
    .m_araddr_o(ma_araddr), .m_arprot_o(ma_arprot), .m_arvalid_o(ma_arvalid), .m_arready_i(x_arready && !direct),
    .m_rdata_i(x_rdata), .m_rresp_i(x_rresp), .m_rvalid_i(x_rvalid && !direct), .m_rready_o(ma_rready)
  );

  axi_lite_xbar_1x2 u_xbar (
    .clk_i(clk), .rst_ni(rst_n),
    .s_awaddr_i(x_awaddr), .s_awprot_i(x_awprot), .s_awvalid_i(x_awvalid), .s_awready_o(x_awready),
    .s_wdata_i(x_wdata), .s_wstrb_i(x_wstrb), .s_wvalid_i(x_wvalid), .s_wready_o(x_wready),
    .s_bresp_o(x_bresp), .s_bvalid_o(x_bvalid), .s_bready_i(x_bready),
    .s_araddr_i(x_araddr), .s_arprot_i(x_arprot), .s_arvalid_i(x_arvalid), .s_arready_o(x_arready),
    .s_rdata_o(x_rdata), .s_rresp_o(x_rresp), .s_rvalid_o(x_rvalid), .s_rready_i(x_rready),
    .m0_awaddr_o(m0_awaddr), .m0_awprot_o(m0_awprot), .m0_awvalid_o(m0_awvalid), .m0_awready_i(m0_awready),
    .m0_wdata_o(m0_wdata), .m0_wstrb_o(m0_wstrb), .m0_wvalid_o(m0_wvalid), .m0_wready_i(m0_wready),
    .m0_bresp_i(m0_bresp), .m0_bvalid_i(m0_bvalid), .m0_bready_o(m0_bready),
    .m0_araddr_o(m0_araddr), .m0_arprot_o(m0_arprot), .m0_arvalid_o(m0_arvalid), .m0_arready_i(m0_arready),
    .m0_rdata_i(m0_rdata), .m0_rresp_i(m0_rresp), .m0_rvalid_i(m0_rvalid), .m0_rready_o(m0_rready),
    .m1_awaddr_o(m1_awaddr), .m1_awprot_o(m1_awprot), .m1_awvalid_o(m1_awvalid), .m1_awready_i(m1_awready),
    .m1_wdata_o(m1_wdata), .m1_wstrb_o(m1_wstrb), .m1_wvalid_o(m1_wvalid), .m1_wready_i(m1_wready),
    .m1_bresp_i(m1_bresp), .m1_bvalid_i(m1_bvalid), .m1_bready_o(m1_bready),
    .m1_araddr_o(m1_araddr), .m1_arprot_o(m1_arprot), .m1_arvalid_o(m1_arvalid), .m1_arready_i(m1_arready),
    .m1_rdata_i(m1_rdata), .m1_rresp_i(m1_rresp), .m1_rvalid_i(m1_rvalid), .m1_rready_o(m1_rready)
  );

  axi_lite_sram #(
    .DEPTH(4096), .AW(12),
    .INIT_FILE_B0(INIT_B0), .INIT_FILE_B1(INIT_B1), .INIT_FILE_B2(INIT_B2), .INIT_FILE_B3(INIT_B3)
  ) u_sram (
    .clk_i(clk), .rst_ni(rst_n),
    .s_awaddr_i(m0_awaddr), .s_awprot_i(m0_awprot), .s_awvalid_i(m0_awvalid), .s_awready_o(m0_awready),
    .s_wdata_i(m0_wdata), .s_wstrb_i(m0_wstrb), .s_wvalid_i(m0_wvalid), .s_wready_o(m0_wready),
    .s_bresp_o(m0_bresp), .s_bvalid_o(m0_bvalid), .s_bready_i(m0_bready),
    .s_araddr_i(m0_araddr), .s_arprot_i(m0_arprot), .s_arvalid_i(m0_arvalid), .s_arready_o(m0_arready),
    .s_rdata_o(m0_rdata), .s_rresp_o(m0_rresp), .s_rvalid_o(m0_rvalid), .s_rready_i(m0_rready)
  );

  axi_lite_to_apb #(.SLOT_EN(16'h003F)) u_bridge (
    .clk_i(clk), .rst_ni(rst_n),
    .s_awaddr_i(m1_awaddr), .s_awprot_i(m1_awprot), .s_awvalid_i(m1_awvalid), .s_awready_o(m1_awready),
    .s_wdata_i(m1_wdata), .s_wstrb_i(m1_wstrb), .s_wvalid_i(m1_wvalid), .s_wready_o(m1_wready),
    .s_bresp_o(m1_bresp), .s_bvalid_o(m1_bvalid), .s_bready_i(m1_bready),
    .s_araddr_i(m1_araddr), .s_arprot_i(m1_arprot), .s_arvalid_i(m1_arvalid), .s_arready_o(m1_arready),
    .s_rdata_o(m1_rdata), .s_rresp_o(m1_rresp), .s_rvalid_o(m1_rvalid), .s_rready_i(m1_rready),
    .psel_o(psel), .penable_o(penable), .pwrite_o(pwrite), .paddr_o(paddr), .pwdata_o(pwdata),
    .pstrb_o(pstrb), .pprot_o(pprot),
    .prdata_i(apb_if_0.prdata), .pready_i(apb_if_0.pready), .pslverr_i(apb_if_0.pslverr)
  );

  // ---------------------------------------------------------------- second master
  wire [31:0] c2_rdata;
  wire        c2_ready, c2_err;
  wire [31:0] s2_awaddr, s2_wdata, s2_araddr;
  wire [2:0]  s2_awprot, s2_arprot;
  wire [3:0]  s2_wstrb;
  wire        s2_awvalid, s2_wvalid, s2_bready, s2_arvalid, s2_rready;

  axi_lite_master u_m2 (
    .clk_i(clk), .rst_ni(rst_n),
    .mem_req_i(cpu_if_1.req), .mem_instr_i(cpu_if_1.instr), .mem_we_i(cpu_if_1.we), .mem_wstrb_i(cpu_if_1.wstrb),
    .mem_addr_i(cpu_if_1.addr), .mem_wdata_i(cpu_if_1.wdata), .mem_rdata_o(c2_rdata),
    .mem_ready_o(c2_ready), .mem_err_o(c2_err),
    .m_awaddr_o(s2_awaddr), .m_awprot_o(s2_awprot), .m_awvalid_o(s2_awvalid), .m_awready_i(axi_if_2.awready),
    .m_wdata_o(s2_wdata), .m_wstrb_o(s2_wstrb), .m_wvalid_o(s2_wvalid), .m_wready_i(axi_if_2.wready),
    .m_bresp_i(axi_if_2.bresp), .m_bvalid_i(axi_if_2.bvalid), .m_bready_o(s2_bready),
    .m_araddr_o(s2_araddr), .m_arprot_o(s2_arprot), .m_arvalid_o(s2_arvalid), .m_arready_i(axi_if_2.arready),
    .m_rdata_i(axi_if_2.rdata), .m_rresp_i(axi_if_2.rresp), .m_rvalid_i(axi_if_2.rvalid), .m_rready_o(s2_rready)
  );

  // ---------------------------------------------------------------- DUT outputs into the interfaces
  // Event-controlled blocks, not assign (Verilator 5.020: "Input combinational
  // region did not converge").
  always @(rst_n) begin
    cpu_if_0.rst_n <= rst_n; cpu_if_1.rst_n <= rst_n;
    axi_direct.rst_n <= rst_n; axi_if_0.rst_n <= rst_n; axi_if_1.rst_n <= rst_n; axi_if_2.rst_n <= rst_n;
    apb_if_0.rst_n <= rst_n;
  end
  always @(mem_rdata or mem_ready or mem_err or c2_rdata or c2_ready or c2_err) begin
    cpu_if_0.rdata <= mem_rdata; cpu_if_0.ready <= mem_ready; cpu_if_0.err <= mem_err;
    cpu_if_1.rdata <= c2_rdata;  cpu_if_1.ready <= c2_ready;  cpu_if_1.err <= c2_err;
  end
  // answers of the xbar to the direct port
  always @(x_awready or x_wready or x_bvalid or x_bresp or x_arready or x_rvalid or x_rresp or x_rdata) begin
    axi_direct.awready <= x_awready; axi_direct.wready <= x_wready;
    axi_direct.bvalid  <= x_bvalid;  axi_direct.bresp  <= x_bresp;
    axi_direct.arready <= x_arready; axi_direct.rvalid <= x_rvalid;
    axi_direct.rresp   <= x_rresp;   axi_direct.rdata  <= x_rdata;
  end
  // xbar input
  always @(x_awaddr or x_awprot or x_awvalid or x_awready or x_wdata or x_wstrb or x_wvalid or x_wready or x_bresp or x_bvalid or x_bready or x_araddr or x_arprot or x_arvalid or x_arready or x_rdata or x_rresp or x_rvalid or x_rready or direct) begin
    axi_if_0.awaddr <= x_awaddr; axi_if_0.awprot <= x_awprot; axi_if_0.awvalid <= x_awvalid; axi_if_0.awready <= x_awready;
    axi_if_0.wdata  <= x_wdata;  axi_if_0.wstrb  <= x_wstrb;  axi_if_0.wvalid  <= x_wvalid;  axi_if_0.wready  <= x_wready;
    axi_if_0.bresp  <= x_bresp;  axi_if_0.bvalid <= x_bvalid; axi_if_0.bready  <= x_bready;
    axi_if_0.araddr <= x_araddr; axi_if_0.arprot <= x_arprot; axi_if_0.arvalid <= x_arvalid; axi_if_0.arready <= x_arready;
    axi_if_0.rdata  <= x_rdata;  axi_if_0.rresp  <= x_rresp;  axi_if_0.rvalid  <= x_rvalid;  axi_if_0.rready  <= x_rready;
    axi_if_0.direct <= direct;
  end
  // SRAM port of the xbar
  always @(m0_awaddr or m0_awprot or m0_awvalid or m0_awready or m0_wdata or m0_wstrb or m0_wvalid or m0_wready or m0_bresp or m0_bvalid or m0_bready or m0_araddr or m0_arprot or m0_arvalid or m0_arready or m0_rdata or m0_rresp or m0_rvalid or m0_rready) begin
    axi_if_1.awaddr <= m0_awaddr; axi_if_1.awprot <= m0_awprot; axi_if_1.awvalid <= m0_awvalid; axi_if_1.awready <= m0_awready;
    axi_if_1.wdata  <= m0_wdata;  axi_if_1.wstrb  <= m0_wstrb;  axi_if_1.wvalid  <= m0_wvalid;  axi_if_1.wready  <= m0_wready;
    axi_if_1.bresp  <= m0_bresp;  axi_if_1.bvalid <= m0_bvalid; axi_if_1.bready  <= m0_bready;
    axi_if_1.araddr <= m0_araddr; axi_if_1.arprot <= m0_arprot; axi_if_1.arvalid <= m0_arvalid; axi_if_1.arready <= m0_arready;
    axi_if_1.rdata  <= m0_rdata;  axi_if_1.rresp  <= m0_rresp;  axi_if_1.rvalid  <= m0_rvalid;  axi_if_1.rready  <= m0_rready;
    axi_if_1.direct <= 1'b0;
  end
  // second master outputs
  always @(s2_awaddr or s2_awprot or s2_awvalid or s2_wdata or s2_wstrb or s2_wvalid or s2_bready or s2_araddr or s2_arprot or s2_arvalid or s2_rready) begin
    axi_if_2.awaddr <= s2_awaddr; axi_if_2.awprot <= s2_awprot; axi_if_2.awvalid <= s2_awvalid;
    axi_if_2.wdata  <= s2_wdata;  axi_if_2.wstrb  <= s2_wstrb;  axi_if_2.wvalid  <= s2_wvalid;
    axi_if_2.bready <= s2_bready;
    axi_if_2.araddr <= s2_araddr; axi_if_2.arprot <= s2_arprot; axi_if_2.arvalid <= s2_arvalid;
    axi_if_2.rready <= s2_rready;
    axi_if_2.direct <= 1'b0;
  end
  // APB request signals of the bridge
  always @(psel or penable or pwrite or paddr or pwdata or pstrb or pprot) begin
    apb_if_0.psel <= psel; apb_if_0.penable <= penable; apb_if_0.pwrite <= pwrite; apb_if_0.paddr <= paddr;
    apb_if_0.pwdata <= pwdata; apb_if_0.pstrb <= pstrb; apb_if_0.pprot <= pprot;
  end

  // 50 MHz clock
  initial begin
    clk = 1'b0;
    forever begin
      #10ns;
      clk = ~clk;
    end
  end

  initial begin
    rst_n = 1'b0;
    #100ns rst_n = 1'b1;
  end

  initial begin
    #20ms;
    $display("[testbench] Time out....Seems your tb is hang!");
    $display("TEST FAILED");
    $finish;
  end

  bus_base_test   test;
  bus_decode_test decode_test;
  bus_sram_test   sram_test;
  bus_apb_test    apb_test;
  bus_master_test master_test;
  bus_rand_test   rand_test;

  initial begin
    if ($test$plusargs("bus_decode_test")) begin
      $display("%0t: [testbench] Run bus_decode_test", $time);
      decode_test = new();
      test = decode_test;
    end
    else if ($test$plusargs("bus_sram_test")) begin
      $display("%0t: [testbench] Run bus_sram_test", $time);
      sram_test = new();
      test = sram_test;
    end
    else if ($test$plusargs("bus_apb_test")) begin
      $display("%0t: [testbench] Run bus_apb_test", $time);
      apb_test = new();
      test = apb_test;
    end
    else if ($test$plusargs("bus_master_test")) begin
      $display("%0t: [testbench] Run bus_master_test", $time);
      master_test = new();
      test = master_test;
    end
    else if ($test$plusargs("bus_rand_test")) begin
      $display("%0t: [testbench] Run bus_rand_test", $time);
      rand_test = new();
      test = rand_test;
    end
    else begin
      $display("%0t: [testbench] Run bus_base_test", $time);
      test = new();
    end
    test.cpu0_vif = cpu_if_0;
    test.cpu1_vif = cpu_if_1;
    test.axd_vif  = axi_direct;
    test.ax0_vif  = axi_if_0;
    test.ax1_vif  = axi_if_1;
    test.ax2_vif  = axi_if_2;
    test.apb_vif  = apb_if_0;
    test.run_test();
  end
endmodule
