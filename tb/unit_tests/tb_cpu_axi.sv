// CPU + bus subsystem testbench: cpu_wrapper -> axi_lite_master ->
// axi_lite_xbar_1x2 -> {axi_lite_sram 16 KB, axi_lite_to_apb}. Runs the
// riscv-tests through the real AXI4-Lite path (scripts/run_riscv_tests.sh
// with TB=cpu_axi). APB slot 0 is a test register, slot 1 answers PSLVERR,
// slots 2..5 read 0; slots 6..15 are disabled in the bridge (SLVERR).
// Plusargs: +HEX=<word file> +TOHOST=<hex> +MAXCYC=<n> (as tb_cpu_wrapper).
// Checks: AXI VALID stays High until READY, address/data stable while
// waiting, one outstanding transaction. Ends with TEST PASSED / TEST FAILED.
`timescale 1ns/1ps
module tb_cpu_axi;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  string       hex_file;
  logic [31:0] tohost;
  int unsigned max_cyc;
  int unsigned cycle = 0;
  int unsigned errors = 0;
  logic [31:0] words [4096];

  // CPU port
  wire        mem_req, mem_instr, mem_we, mem_ready, mem_err;
  wire [3:0]  mem_wstrb;
  wire [31:0] mem_addr, mem_wdata, mem_rdata;

  cpu_wrapper u_cpu (
    .clk_i (clk), .rst_ni (rst_n),
    .mem_req_o (mem_req), .mem_instr_o (mem_instr), .mem_we_o (mem_we),
    .mem_wstrb_o (mem_wstrb), .mem_addr_o (mem_addr), .mem_wdata_o (mem_wdata),
    .mem_rdata_i (mem_rdata), .mem_ready_i (mem_ready), .mem_err_i (mem_err),
    .irq_mtip_i (1'b0), .irq_meip_i (1'b0)
  );

  // AXI between master and xbar (m_), xbar and SRAM (s0_), xbar and bridge (s1_)
  wire [31:0] m_awaddr,  s0_awaddr,  s1_awaddr;
  wire [2:0]  m_awprot,  s0_awprot,  s1_awprot;
  wire        m_awvalid, s0_awvalid, s1_awvalid;
  wire        m_awready, s0_awready, s1_awready;
  wire [31:0] m_wdata,   s0_wdata,   s1_wdata;
  wire [3:0]  m_wstrb,   s0_wstrb,   s1_wstrb;
  wire        m_wvalid,  s0_wvalid,  s1_wvalid;
  wire        m_wready,  s0_wready,  s1_wready;
  wire [1:0]  m_bresp,   s0_bresp,   s1_bresp;
  wire        m_bvalid,  s0_bvalid,  s1_bvalid;
  wire        m_bready,  s0_bready,  s1_bready;
  wire [31:0] m_araddr,  s0_araddr,  s1_araddr;
  wire [2:0]  m_arprot,  s0_arprot,  s1_arprot;
  wire        m_arvalid, s0_arvalid, s1_arvalid;
  wire        m_arready, s0_arready, s1_arready;
  wire [31:0] m_rdata,   s0_rdata,   s1_rdata;
  wire [1:0]  m_rresp,   s0_rresp,   s1_rresp;
  wire        m_rvalid,  s0_rvalid,  s1_rvalid;
  wire        m_rready,  s0_rready,  s1_rready;

  axi_lite_master u_master (
    .clk_i (clk), .rst_ni (rst_n),
    .mem_req_i (mem_req), .mem_instr_i (mem_instr), .mem_we_i (mem_we),
    .mem_wstrb_i (mem_wstrb), .mem_addr_i (mem_addr), .mem_wdata_i (mem_wdata),
    .mem_rdata_o (mem_rdata), .mem_ready_o (mem_ready), .mem_err_o (mem_err),
    .m_awaddr_o (m_awaddr), .m_awprot_o (m_awprot), .m_awvalid_o (m_awvalid), .m_awready_i (m_awready),
    .m_wdata_o (m_wdata), .m_wstrb_o (m_wstrb), .m_wvalid_o (m_wvalid), .m_wready_i (m_wready),
    .m_bresp_i (m_bresp), .m_bvalid_i (m_bvalid), .m_bready_o (m_bready),
    .m_araddr_o (m_araddr), .m_arprot_o (m_arprot), .m_arvalid_o (m_arvalid), .m_arready_i (m_arready),
    .m_rdata_i (m_rdata), .m_rresp_i (m_rresp), .m_rvalid_i (m_rvalid), .m_rready_o (m_rready)
  );

  axi_lite_xbar_1x2 u_xbar (
    .clk_i (clk), .rst_ni (rst_n),
    .s_awaddr_i (m_awaddr), .s_awprot_i (m_awprot), .s_awvalid_i (m_awvalid), .s_awready_o (m_awready),
    .s_wdata_i (m_wdata), .s_wstrb_i (m_wstrb), .s_wvalid_i (m_wvalid), .s_wready_o (m_wready),
    .s_bresp_o (m_bresp), .s_bvalid_o (m_bvalid), .s_bready_i (m_bready),
    .s_araddr_i (m_araddr), .s_arprot_i (m_arprot), .s_arvalid_i (m_arvalid), .s_arready_o (m_arready),
    .s_rdata_o (m_rdata), .s_rresp_o (m_rresp), .s_rvalid_o (m_rvalid), .s_rready_i (m_rready),
    .m0_awaddr_o (s0_awaddr), .m0_awprot_o (s0_awprot), .m0_awvalid_o (s0_awvalid), .m0_awready_i (s0_awready),
    .m0_wdata_o (s0_wdata), .m0_wstrb_o (s0_wstrb), .m0_wvalid_o (s0_wvalid), .m0_wready_i (s0_wready),
    .m0_bresp_i (s0_bresp), .m0_bvalid_i (s0_bvalid), .m0_bready_o (s0_bready),
    .m0_araddr_o (s0_araddr), .m0_arprot_o (s0_arprot), .m0_arvalid_o (s0_arvalid), .m0_arready_i (s0_arready),
    .m0_rdata_i (s0_rdata), .m0_rresp_i (s0_rresp), .m0_rvalid_i (s0_rvalid), .m0_rready_o (s0_rready),
    .m1_awaddr_o (s1_awaddr), .m1_awprot_o (s1_awprot), .m1_awvalid_o (s1_awvalid), .m1_awready_i (s1_awready),
    .m1_wdata_o (s1_wdata), .m1_wstrb_o (s1_wstrb), .m1_wvalid_o (s1_wvalid), .m1_wready_i (s1_wready),
    .m1_bresp_i (s1_bresp), .m1_bvalid_i (s1_bvalid), .m1_bready_o (s1_bready),
    .m1_araddr_o (s1_araddr), .m1_arprot_o (s1_arprot), .m1_arvalid_o (s1_arvalid), .m1_arready_i (s1_arready),
    .m1_rdata_i (s1_rdata), .m1_rresp_i (s1_rresp), .m1_rvalid_i (s1_rvalid), .m1_rready_o (s1_rready)
  );

  axi_lite_sram u_sram (
    .clk_i (clk), .rst_ni (rst_n),
    .s_awaddr_i (s0_awaddr), .s_awprot_i (s0_awprot), .s_awvalid_i (s0_awvalid), .s_awready_o (s0_awready),
    .s_wdata_i (s0_wdata), .s_wstrb_i (s0_wstrb), .s_wvalid_i (s0_wvalid), .s_wready_o (s0_wready),
    .s_bresp_o (s0_bresp), .s_bvalid_o (s0_bvalid), .s_bready_i (s0_bready),
    .s_araddr_i (s0_araddr), .s_arprot_i (s0_arprot), .s_arvalid_i (s0_arvalid), .s_arready_o (s0_arready),
    .s_rdata_o (s0_rdata), .s_rresp_o (s0_rresp), .s_rvalid_o (s0_rvalid), .s_rready_i (s0_rready)
  );

  wire [15:0]  psel, pready, pslverr;
  wire         penable, pwrite;
  wire [11:0]  paddr;
  wire [31:0]  pwdata;
  wire [3:0]   pstrb;
  wire [2:0]   pprot;
  logic [511:0] prdata;
  logic [31:0] test_reg = 32'd0;

  axi_lite_to_apb u_bridge (
    .clk_i (clk), .rst_ni (rst_n),
    .s_awaddr_i (s1_awaddr), .s_awprot_i (s1_awprot), .s_awvalid_i (s1_awvalid), .s_awready_o (s1_awready),
    .s_wdata_i (s1_wdata), .s_wstrb_i (s1_wstrb), .s_wvalid_i (s1_wvalid), .s_wready_o (s1_wready),
    .s_bresp_o (s1_bresp), .s_bvalid_o (s1_bvalid), .s_bready_i (s1_bready),
    .s_araddr_i (s1_araddr), .s_arprot_i (s1_arprot), .s_arvalid_i (s1_arvalid), .s_arready_o (s1_arready),
    .s_rdata_o (s1_rdata), .s_rresp_o (s1_rresp), .s_rvalid_o (s1_rvalid), .s_rready_i (s1_rready),
    .psel_o (psel), .penable_o (penable), .pwrite_o (pwrite), .paddr_o (paddr), .pwdata_o (pwdata),
    .pstrb_o (pstrb), .pprot_o (pprot), .prdata_i (prdata), .pready_i (pready), .pslverr_i (pslverr)
  );

  // APB test slaves: slot 0 = one RW register with byte strobes (2 wait states),
  // slot 1 = PSLVERR, others read 0
  int unsigned apb_wait = 0;
  assign pready  = {15'h7FFF, (apb_wait == 2)};
  assign pslverr = {14'd0, psel[1], 1'b0};
  always_comb begin
    prdata = '0;
    prdata[31:0] = test_reg;
  end
  always @(posedge clk) begin
    if (psel[0] && penable && !pready[0]) apb_wait <= apb_wait + 1;
    else                                  apb_wait <= 0;
    if (psel[0] && penable && pready[0] && pwrite)
      for (int b = 0; b < 4; b++) if (pstrb[b]) test_reg[8*b +: 8] <= pwdata[8*b +: 8];
  end

  // ---------------- protocol checks on the master side ----------------
  logic        awv_q = 0, wv_q = 0, arv_q = 0, awr_q, wr_q, arr_q;
  logic [31:0] awa_q, wd_q, ara_q;
  always @(posedge clk) begin
    if (rst_n) begin
      if (awv_q && !awr_q && (!m_awvalid || m_awaddr != awa_q))
        begin errors++; $display("[%0t] ERROR: AW dropped or changed before AWREADY", $time); end
      if (wv_q && !wr_q && (!m_wvalid || m_wdata != wd_q))
        begin errors++; $display("[%0t] ERROR: W dropped or changed before WREADY", $time); end
      if (arv_q && !arr_q && (!m_arvalid || m_araddr != ara_q))
        begin errors++; $display("[%0t] ERROR: AR dropped or changed before ARREADY", $time); end
      if (m_arvalid && (m_awvalid || m_wvalid))
        begin errors++; $display("[%0t] ERROR: read and write outstanding together", $time); end
    end
    awv_q <= m_awvalid; awr_q <= m_awready; awa_q <= m_awaddr;
    wv_q  <= m_wvalid;  wr_q  <= m_wready;  wd_q  <= m_wdata;
    arv_q <= m_arvalid; arr_q <= m_arready; ara_q <= m_araddr;
  end

  // ---------------- tohost ----------------
  task automatic finish_test();
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED");
    $finish;
  endtask

  always @(posedge clk) begin
    cycle <= cycle + 1;
    if (s0_awvalid && s0_awready && s0_awaddr == tohost) begin
      if (s0_wdata == 32'd1) begin
        $display("[%0t] tohost = 1 after %0d cycles", $time, cycle);
      end else begin
        $display("[%0t] ERROR: tohost = 0x%08h (failed test number %0d)", $time, s0_wdata, s0_wdata >> 1);
        errors++;
      end
      finish_test();
    end
    if (cycle >= max_cyc) begin
      $display("[%0t] ERROR: timeout after %0d cycles", $time, cycle);
      errors++;
      finish_test();
    end
  end

  initial begin
    if (!$value$plusargs("HEX=%s", hex_file)) begin
      $display("ERROR: +HEX=<file> missing");
      $display("TEST FAILED");
      $finish;
    end
    if (!$value$plusargs("TOHOST=%h", tohost)) tohost = 32'hFFFF_FFFF;
    if (!$value$plusargs("MAXCYC=%d", max_cyc)) max_cyc = 400000;
    foreach (words[i]) words[i] = 32'd0;
    $readmemh(hex_file, words);
    foreach (words[i]) begin
      u_sram.u_ram.lane0[i] = words[i][7:0];
      u_sram.u_ram.lane1[i] = words[i][15:8];
      u_sram.u_ram.lane2[i] = words[i][23:16];
      u_sram.u_ram.lane3[i] = words[i][31:24];
    end
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
  end

endmodule
