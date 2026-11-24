`timescale 1ns/1ps
// Directed, self-checking testbench for the bus subsystem (vplan sheet BUS):
//   CPU port BFM -> axi_lite_master -> axi_lite_xbar_1x2 -> axi_lite_sram (16 KB)
//                                                        -> axi_lite_to_apb -> APB slave model (16 slots)
// A direct AXI4-Lite BFM can take the place of the master adapter on the
// interconnect input (BUS-13: AW/W and AR in the same cycle).
// A second axi_lite_master (u_m2) talks to an AXI4-Lite slave model with
// random READY / response delays and a chosen response code (BUS-14..16).
// The APB slave model has, per slot, 1024 words of memory, a wait-state count
// and PSLVERR flags; its monitor checks SETUP / ACCESS, signal stability and
// that at most one PSEL is High, and logs every transfer.
// BUS-17 (load / store / fetch faults seen by the CPU) is a program:
// make riscv-tests TB=cpu_axi SUITES=bus. It is listed as EXT here.
// The log ends with a PASS / FAIL / NOT RUN line per item, then
// "TEST PASSED" or "TEST FAILED" for scripts/check_log.sh.
module tb_bus_sys;

  localparam int CLK_NS = 20;

  // $readmemh paths are relative to the simulator's working directory:
  // sim/ for Verilator, sim/work/ for XSim.
// Plain (untyped) string parameters, as a Verilog-2005 module expects them.
`ifdef VERILATOR
  localparam TV = "../tb/test_vectors/";
`else
  localparam TV = "../../tb/test_vectors/";
`endif
  localparam INIT_B0 = {TV, "bus_init_b0.hex"};
  localparam INIT_B1 = {TV, "bus_init_b1.hex"};
  localparam INIT_B2 = {TV, "bus_init_b2.hex"};
  localparam INIT_B3 = {TV, "bus_init_b3.hex"};

  localparam logic [1:0] OKAY = 2'b00, EXOKAY = 2'b01, SLVERR = 2'b10, DECERR = 2'b11;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #(CLK_NS / 2) clk = ~clk;

  `include "vplan/vp_bus.svh"

  task automatic check(input bit ok, input string what);
    vplan_pkg::chk(ok, what);
  endtask

  task automatic check_at(input string id, input bit ok, input string what);
    vplan_pkg::chk_at(id, ok, what);
  endtask

  task automatic item(input string id);
    vplan_pkg::item(id);
  endtask

  // ================================================================ main path
  // CPU memory port
  logic        mem_req = 1'b0, mem_instr = 1'b0, mem_we = 1'b0;
  logic [3:0]  mem_wstrb = 4'h0;
  logic [31:0] mem_addr = 32'h0, mem_wdata = 32'h0;
  wire  [31:0] mem_rdata;
  wire         mem_ready, mem_err;

  // master adapter AXI outputs
  wire [31:0] ma_awaddr, ma_wdata, ma_araddr;
  wire [2:0]  ma_awprot, ma_arprot;
  wire [3:0]  ma_wstrb;
  wire        ma_awvalid, ma_wvalid, ma_bready, ma_arvalid, ma_rready;

  // direct AXI BFM
  logic        direct = 1'b0;
  logic [31:0] d_awaddr = 32'h0, d_wdata = 32'h0, d_araddr = 32'h0;
  logic [2:0]  d_awprot = 3'b001, d_arprot = 3'b001;
  logic [3:0]  d_wstrb = 4'h0;
  logic        d_awvalid = 1'b0, d_wvalid = 1'b0, d_bready = 1'b0, d_arvalid = 1'b0, d_rready = 1'b0;

  // interconnect slave port
  wire [31:0] x_awaddr  = direct ? d_awaddr  : ma_awaddr;
  wire [2:0]  x_awprot  = direct ? d_awprot  : ma_awprot;
  wire        x_awvalid = direct ? d_awvalid : ma_awvalid;
  wire [31:0] x_wdata   = direct ? d_wdata   : ma_wdata;
  wire [3:0]  x_wstrb   = direct ? d_wstrb   : ma_wstrb;
  wire        x_wvalid  = direct ? d_wvalid  : ma_wvalid;
  wire        x_bready  = direct ? d_bready  : ma_bready;
  wire [31:0] x_araddr  = direct ? d_araddr  : ma_araddr;
  wire [2:0]  x_arprot  = direct ? d_arprot  : ma_arprot;
  wire        x_arvalid = direct ? d_arvalid : ma_arvalid;
  wire        x_rready  = direct ? d_rready  : ma_rready;
  wire        x_awready, x_wready, x_bvalid, x_arready, x_rvalid;
  wire [1:0]  x_bresp, x_rresp;
  wire [31:0] x_rdata;

  // interconnect master ports
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

  // APB
  wire [15:0]  psel;
  wire         penable, pwrite;
  wire [11:0]  paddr;
  wire [31:0]  pwdata;
  wire [3:0]   pstrb;
  wire [2:0]   pprot;
  wire [511:0] prdata;
  wire [15:0]  pready, pslverr;

  axi_lite_master u_mst (
    .clk_i(clk), .rst_ni(rst_n),
    .mem_req_i(mem_req), .mem_instr_i(mem_instr), .mem_we_i(mem_we), .mem_wstrb_i(mem_wstrb),
    .mem_addr_i(mem_addr), .mem_wdata_i(mem_wdata), .mem_rdata_o(mem_rdata),
    .mem_ready_o(mem_ready), .mem_err_o(mem_err),
    .m_awaddr_o(ma_awaddr), .m_awprot_o(ma_awprot), .m_awvalid_o(ma_awvalid),
    .m_awready_i(x_awready && !direct),
    .m_wdata_o(ma_wdata), .m_wstrb_o(ma_wstrb), .m_wvalid_o(ma_wvalid), .m_wready_i(x_wready && !direct),
    .m_bresp_i(x_bresp), .m_bvalid_i(x_bvalid && !direct), .m_bready_o(ma_bready),
    .m_araddr_o(ma_araddr), .m_arprot_o(ma_arprot), .m_arvalid_o(ma_arvalid),
    .m_arready_i(x_arready && !direct),
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
    .pstrb_o(pstrb), .pprot_o(pprot), .prdata_i(prdata), .pready_i(pready), .pslverr_i(pslverr)
  );

  // ================================================================ APB slave model
  logic [31:0] amem [16][1024];
  int          wait_n [16];
  bit          err_rd [16];
  bit          err_wr [16];
  logic [31:0] prd_q [16];
  int          acnt = 0;

  for (genvar g = 0; g < 16; g++) begin : g_apb
    assign prdata[32*g +: 32] = prd_q[g];
    assign pready[g]  = psel[g] && penable && (acnt >= wait_n[g]);
    assign pslverr[g] = pready[g] && (pwrite ? err_wr[g] : err_rd[g]);
  end

  typedef struct {
    int          slot;
    logic [11:0] addr;
    bit          wr;
    logic [31:0] wdata;
    logic [3:0]  strb;
    logic [2:0]  prot;
    int          waits;
  } apb_t;
  apb_t apb_log[$];

  int          ph = 0;               // 0 idle, 1 inside a transfer
  int          cur_slot;
  logic [15:0] c_sel;
  logic [11:0] c_addr;
  logic        c_write;
  logic [31:0] c_wdata;
  logic [3:0]  c_strb;
  logic [2:0]  c_prot;
  int          c_waits;
  apb_t        ent;

  function automatic int slot_of(input logic [15:0] s);
    for (int i = 0; i < 16; i++) if (s[i]) return i;
    return -1;
  endfunction

  always @(posedge clk) begin
    if (rst_n) begin
      check_at("BUS-05", psel[15:6] == 10'd0, $sformatf("PSEL of a disabled slot asserted: %b", psel));
      if (psel != 16'd0) begin
        check_at("BUS-04", $onehot(psel), $sformatf("more than one PSEL: %b", psel));
        if (ph == 0) begin
          // SETUP
          check_at("BUS-09", penable === 1'b0, "first PSEL cycle is not SETUP (PENABLE = 1)");
          c_sel = psel; c_addr = paddr; c_write = pwrite; c_wdata = pwdata; c_strb = pstrb; c_prot = pprot;
          c_waits = 0;
          cur_slot = slot_of(psel);
          ph = 1;
          acnt <= 0;
          prd_q[cur_slot] <= amem[cur_slot][paddr[11:2]];
        end else begin
          // ACCESS
          check_at("BUS-09", penable === 1'b1, "PENABLE not 1 in the cycle after SETUP");
          check_at("BUS-09", psel == c_sel && paddr == c_addr && pwrite == c_write && pwdata == c_wdata &&
                             pstrb == c_strb && pprot == c_prot,
                   "PSEL / PADDR / PWRITE / PWDATA / PSTRB / PPROT changed between SETUP and ACCESS");
          if (pready[cur_slot]) begin
            ent.slot = cur_slot; ent.addr = c_addr; ent.wr = c_write; ent.wdata = c_wdata;
            ent.strb = c_strb; ent.prot = c_prot; ent.waits = c_waits;
            apb_log.push_back(ent);
            if (c_write && !err_wr[cur_slot])
              for (int b = 0; b < 4; b++)
                if (c_strb[b]) amem[cur_slot][c_addr[11:2]][8*b +: 8] = c_wdata[8*b +: 8];
            ph = 0;
            acnt <= 0;
          end else begin
            c_waits++;
            acnt <= acnt + 1;
          end
        end
      end else begin
        check_at("BUS-11", ph == 0, "PSEL dropped before PREADY");
        ph = 0;
      end
    end
  end

  // ================================================================ other monitors
  int n_sram_hs = 0;                 // SRAM AW and AR handshakes
  int sram_rd_pend = 0;
  int n_ready = 0;                   // mem_ready pulses
  logic [1:0] last_bresp = 2'b00, last_rresp = 2'b00;

  always @(posedge clk) begin
    if (rst_n) begin
      // BUS-07: R from the SRAM only after its AR handshake
      if (m0_rvalid) check_at("BUS-07", sram_rd_pend > 0, "SRAM RVALID without an earlier AR handshake");
      if (m0_arvalid && m0_arready) begin sram_rd_pend++; n_sram_hs++; end
      if (m0_rvalid && m0_rready)   sram_rd_pend--;
      if (m0_awvalid && m0_awready) n_sram_hs++;
      if (x_bvalid && x_bready) last_bresp = x_bresp;
      if (x_rvalid && x_rready) last_rresp = x_rresp;
      if (mem_ready) begin
        n_ready++;
        check_at("BUS-15", mem_req === 1'b1, "mem_ready without a request");
      end
    end
  end

  // ================================================================ CPU port BFM
  // One request; keep = 1 leaves mem_req High so the next call follows
  // without an idle cycle (back to back).
  task automatic cpu(input bit we, input bit instr, input logic [31:0] a, input logic [31:0] wd,
                     input logic [3:0] st, output logic [31:0] rd, output bit err, input bit keep = 1'b0);
    int n0, cyc;
    if (mem_req !== 1'b1) begin
      @(posedge clk); #1;
    end
    n0 = n_ready;
    cyc = 0;
    mem_req = 1'b1; mem_we = we; mem_instr = instr; mem_addr = a; mem_wdata = wd;
    mem_wstrb = we ? st : 4'h0;
    do begin
      @(negedge clk);
      cyc++;
    end while (mem_ready !== 1'b1 && cyc < 500);
    check(mem_ready === 1'b1, $sformatf("no mem_ready for %s 0x%08h", we ? "write" : "read", a));
    rd = mem_rdata;
    err = mem_err;
    @(posedge clk); #1;
    check_at("BUS-15", n_ready - n0 == 1, $sformatf("%0d mem_ready pulses for one request", n_ready - n0));
    if (!keep) begin
      mem_req = 1'b0; mem_we = 1'b0; mem_instr = 1'b0; mem_wstrb = 4'h0;
    end
  endtask

  task automatic wr(input logic [31:0] a, input logic [31:0] d, input logic [3:0] st,
                    input bit exp_err, input string what);
    logic [31:0] rd;
    bit err;
    cpu(1'b1, 1'b0, a, d, st, rd, err);
    check(err == exp_err, $sformatf("%s: write 0x%08h mem_err = %b, expected %b", what, a, err, exp_err));
  endtask

  task automatic rd_exp(input logic [31:0] a, input logic [31:0] exp, input bit exp_err, input string what);
    logic [31:0] rd;
    bit err;
    cpu(1'b0, 1'b0, a, 32'h0, 4'h0, rd, err);
    check(err == exp_err, $sformatf("%s: read 0x%08h mem_err = %b, expected %b", what, a, err, exp_err));
    if (!exp_err) check(rd === exp, $sformatf("%s: read 0x%08h = 0x%08h, expected 0x%08h", what, a, rd, exp));
  endtask

  // ================================================================ second master + AXI slave model
  logic        c2_req = 1'b0, c2_instr = 1'b0, c2_we = 1'b0;
  logic [3:0]  c2_wstrb = 4'h0;
  logic [31:0] c2_addr = 32'h0, c2_wdata = 32'h0;
  wire  [31:0] c2_rdata;
  wire         c2_ready, c2_err;
  wire [31:0]  s2_awaddr, s2_wdata, s2_araddr;
  wire [2:0]   s2_awprot, s2_arprot;
  wire [3:0]   s2_wstrb;
  wire         s2_awvalid, s2_wvalid, s2_bready, s2_arvalid, s2_rready;
  logic        s2_awready = 1'b0, s2_wready = 1'b0, s2_bvalid = 1'b0, s2_arready = 1'b0, s2_rvalid = 1'b0;
  logic [1:0]  s2_bresp = 2'b00, s2_rresp = 2'b00;
  logic [31:0] s2_rdata = 32'h0;

  axi_lite_master u_m2 (
    .clk_i(clk), .rst_ni(rst_n),
    .mem_req_i(c2_req), .mem_instr_i(c2_instr), .mem_we_i(c2_we), .mem_wstrb_i(c2_wstrb),
    .mem_addr_i(c2_addr), .mem_wdata_i(c2_wdata), .mem_rdata_o(c2_rdata),
    .mem_ready_o(c2_ready), .mem_err_o(c2_err),
    .m_awaddr_o(s2_awaddr), .m_awprot_o(s2_awprot), .m_awvalid_o(s2_awvalid), .m_awready_i(s2_awready),
    .m_wdata_o(s2_wdata), .m_wstrb_o(s2_wstrb), .m_wvalid_o(s2_wvalid), .m_wready_i(s2_wready),
    .m_bresp_i(s2_bresp), .m_bvalid_i(s2_bvalid), .m_bready_o(s2_bready),
    .m_araddr_o(s2_araddr), .m_arprot_o(s2_arprot), .m_arvalid_o(s2_arvalid), .m_arready_i(s2_arready),
    .m_rdata_i(s2_rdata), .m_rresp_i(s2_rresp), .m_rvalid_i(s2_rvalid), .m_rready_o(s2_rready)
  );

  // Slave model: READY 0..3 cycles after VALID (never before), response
  // 0..3 cycles after the address (and data) handshake, response code s2_resp.
  logic [1:0]  s2_resp = OKAY;
  int          aw_d = 0, w_d = 0, ar_d = 0, b_d = 0, r_d = 0;
  bit          aw_got = 1'b0, w_got = 1'b0, ar_got = 1'b0;
  logic [31:0] s2_last_awaddr, s2_last_wdata, s2_last_araddr;
  logic [3:0]  s2_last_wstrb;
  logic [2:0]  s2_last_awprot, s2_last_arprot;

  always @(posedge clk) begin
    if (!rst_n) begin
      s2_awready <= 1'b0; s2_wready <= 1'b0; s2_arready <= 1'b0; s2_bvalid <= 1'b0; s2_rvalid <= 1'b0;
    end else begin
      // AW
      if (s2_awvalid && s2_awready) begin
        s2_awready <= 1'b0; aw_got = 1'b1; s2_last_awaddr = s2_awaddr; s2_last_awprot = s2_awprot;
        aw_d = $urandom_range(0, 3);
      end else if (s2_awvalid && !aw_got) begin
        if (aw_d == 0) s2_awready <= 1'b1; else aw_d--;
      end
      // W
      if (s2_wvalid && s2_wready) begin
        s2_wready <= 1'b0; w_got = 1'b1; s2_last_wdata = s2_wdata; s2_last_wstrb = s2_wstrb;
        w_d = $urandom_range(0, 3);
      end else if (s2_wvalid && !w_got) begin
        if (w_d == 0) s2_wready <= 1'b1; else w_d--;
      end
      // B
      if (s2_bvalid && s2_bready) begin
        s2_bvalid <= 1'b0; aw_got = 1'b0; w_got = 1'b0; b_d = $urandom_range(0, 3);
      end else if (aw_got && w_got && !s2_bvalid) begin
        if (b_d == 0) begin s2_bvalid <= 1'b1; s2_bresp <= s2_resp; end else b_d--;
      end
      // AR
      if (s2_arvalid && s2_arready) begin
        s2_arready <= 1'b0; ar_got = 1'b1; s2_last_araddr = s2_araddr; s2_last_arprot = s2_arprot;
        ar_d = $urandom_range(0, 3);
      end else if (s2_arvalid && !ar_got) begin
        if (ar_d == 0) s2_arready <= 1'b1; else ar_d--;
      end
      // R
      if (s2_rvalid && s2_rready) begin
        s2_rvalid <= 1'b0; ar_got = 1'b0; r_d = $urandom_range(0, 3);
      end else if (ar_got && !s2_rvalid) begin
        if (r_d == 0) begin
          s2_rvalid <= 1'b1; s2_rresp <= s2_resp; s2_rdata <= ~s2_last_araddr;
        end else r_d--;
      end
    end
  end

  // BUS-14 monitor: VALID held with stable payload until READY
  logic        p_awv = 1'b0, p_awr = 1'b0, p_wv = 1'b0, p_wr = 1'b0, p_arv = 1'b0, p_arr = 1'b0;
  logic [31:0] p_awaddr, p_wdata, p_araddr;
  logic [3:0]  p_wstrb;
  int          n_c2_ready = 0;

  always @(posedge clk) begin
    if (rst_n) begin
      if (p_awv && !p_awr)
        check_at("BUS-14", s2_awvalid === 1'b1 && s2_awaddr == p_awaddr, "AWVALID / AWADDR changed before AWREADY");
      if (p_wv && !p_wr)
        check_at("BUS-14", s2_wvalid === 1'b1 && s2_wdata == p_wdata && s2_wstrb == p_wstrb,
                 "WVALID / WDATA / WSTRB changed before WREADY");
      if (p_arv && !p_arr)
        check_at("BUS-14", s2_arvalid === 1'b1 && s2_araddr == p_araddr, "ARVALID / ARADDR changed before ARREADY");
      p_awv = s2_awvalid; p_awr = s2_awready; p_awaddr = s2_awaddr;
      p_wv = s2_wvalid; p_wr = s2_wready; p_wdata = s2_wdata; p_wstrb = s2_wstrb;
      p_arv = s2_arvalid; p_arr = s2_arready; p_araddr = s2_araddr;
      if (c2_ready) n_c2_ready++;
    end
  end

  task automatic cpu2(input bit we, input bit instr, input logic [31:0] a, input logic [31:0] wd,
                      input logic [3:0] st, output logic [31:0] rd, output bit err);
    int n0, cyc;
    @(posedge clk); #1;
    n0 = n_c2_ready;
    cyc = 0;
    c2_req = 1'b1; c2_we = we; c2_instr = instr; c2_addr = a; c2_wdata = wd; c2_wstrb = we ? st : 4'h0;
    do begin
      @(negedge clk);
      cyc++;
    end while (c2_ready !== 1'b1 && cyc < 100);
    check(c2_ready === 1'b1, $sformatf("master 2: no mem_ready for 0x%08h (VALID waiting for READY?)", a));
    rd = c2_rdata;
    err = c2_err;
    @(posedge clk); #1;
    check_at("BUS-15", n_c2_ready - n0 == 1, $sformatf("master 2: %0d mem_ready pulses for one request", n_c2_ready - n0));
    c2_req = 1'b0; c2_we = 1'b0; c2_instr = 1'b0; c2_wstrb = 4'h0;
  endtask

  // ================================================================ tests
  logic [31:0] rdv;
  bit          errv;
  int          nlog, nhs;

  task automatic test_init_file();
    $display("-- BUS-08 SRAM init file");
    item("BUS-08");
    rd_exp(32'h0000_0000, 32'h4433_2211, 1'b0, "init file word 0");
    rd_exp(32'h0000_3FFC, 32'h8877_6655, 1'b0, "init file word 0xFFF");
  endtask

  task automatic test_sram_decode();
    $display("-- BUS-01 SRAM in range");
    item("BUS-01");
    nlog = apb_log.size();
    wr(32'h0000_0000, 32'h0123_4567, 4'hF, 1'b0, "SRAM 0x0000");
    wr(32'h0000_2000, 32'h89AB_CDEF, 4'hF, 1'b0, "SRAM 0x2000");
    wr(32'h0000_3FFC, 32'hF0E1_D2C3, 4'hF, 1'b0, "SRAM 0x3FFC");
    check(last_bresp == OKAY, "SRAM write: BRESP OKAY");
    rd_exp(32'h0000_0000, 32'h0123_4567, 1'b0, "SRAM 0x0000");
    rd_exp(32'h0000_2000, 32'h89AB_CDEF, 1'b0, "SRAM 0x2000");
    rd_exp(32'h0000_3FFC, 32'hF0E1_D2C3, 1'b0, "SRAM 0x3FFC");
    check(last_rresp == OKAY, "SRAM read: RRESP OKAY");
    check(apb_log.size() == nlog, "SRAM access started an APB transfer");
  endtask

  task automatic unmapped(input string id, input logic [31:0] a);
    item(id);
    nlog = apb_log.size();
    nhs = n_sram_hs;
    cpu(1'b0, 1'b0, a, 32'h0, 4'h0, rdv, errv);
    check(errv == 1'b1 && last_rresp == DECERR && rdv == 32'h0,
          $sformatf("read 0x%08h: mem_err %b RRESP %b RDATA %h, expected DECERR and 0", a, errv, last_rresp, rdv));
    cpu(1'b1, 1'b0, a, 32'hDEAD_BEEF, 4'hF, rdv, errv);
    check(errv == 1'b1 && last_bresp == DECERR,
          $sformatf("write 0x%08h: mem_err %b BRESP %b, expected DECERR", a, errv, last_bresp));
    check(apb_log.size() == nlog && n_sram_hs == nhs, $sformatf("0x%08h reached the SRAM or the APB bus", a));
  endtask

  task automatic test_apb_slots();
    $display("-- BUS-04 APB slots 0..5");
    item("BUS-04");
    for (int s = 0; s < 6; s++) begin
      logic [31:0] a;
      a = 32'h1000_0000 | (s << 12);
      wr(a, 32'hA500_0000 | s, 4'hF, 1'b0, $sformatf("slot %0d", s));
      check(apb_log.size() > 0 && apb_log[$].slot == s && apb_log[$].addr == 12'h000 && apb_log[$].wr,
            $sformatf("write to slot %0d: APB went to slot %0d addr %h", s, apb_log[$].slot, apb_log[$].addr));
      check(last_bresp == OKAY, $sformatf("slot %0d write: BRESP %b", s, last_bresp));
      rd_exp(a, 32'hA500_0000 | s, 1'b0, $sformatf("slot %0d", s));
      check(apb_log[$].slot == s && !apb_log[$].wr, $sformatf("read of slot %0d: APB slot %0d", s, apb_log[$].slot));
      check(last_rresp == OKAY, $sformatf("slot %0d read: RRESP %b", s, last_rresp));
    end
    // PADDR = ADDR[11:0]
    wr(32'h1000_2ABC, 32'h0000_0ABC, 4'hF, 1'b0, "slot 2 offset 0xABC");
    check(apb_log[$].slot == 2 && apb_log[$].addr == 12'hABC, $sformatf("PADDR %h, expected ABC", apb_log[$].addr));
    rd_exp(32'h1000_2ABC, 32'h0000_0ABC, 1'b0, "slot 2 offset 0xABC");

    $display("-- BUS-05 APB slots 6..15");
    item("BUS-05");
    for (int k = 0; k < 3; k++) begin
      logic [31:0] a;
      a = (k == 0) ? 32'h1000_6000 : (k == 1) ? 32'h1000_A000 : 32'h1000_FFFC;
      nlog = apb_log.size();
      cpu(1'b0, 1'b0, a, 32'h0, 4'h0, rdv, errv);
      check(errv == 1'b1 && last_rresp == SLVERR, $sformatf("read 0x%08h: RRESP %b, expected SLVERR", a, last_rresp));
      cpu(1'b1, 1'b0, a, 32'h1234_5678, 4'hF, rdv, errv);
      check(errv == 1'b1 && last_bresp == SLVERR, $sformatf("write 0x%08h: BRESP %b, expected SLVERR", a, last_bresp));
      check(apb_log.size() == nlog, $sformatf("0x%08h started an APB transfer", a));
    end
  endtask

  task automatic test_sram_strobes();
    logic [31:0] exp;
    logic [3:0]  sv[6];
    $display("-- BUS-06 SRAM byte enables");
    item("BUS-06");
    sv = '{4'b0001, 4'b0010, 4'b0100, 4'b1000, 4'b0011, 4'b1100};
    foreach (sv[k]) begin
      wr(32'h0000_0100, 32'hFFFF_FFFF, 4'hF, 1'b0, "SRAM all ones");
      wr(32'h0000_0100, 32'h0000_0000, sv[k], 1'b0, $sformatf("SRAM WSTRB %b", sv[k]));
      exp = 32'hFFFF_FFFF;
      for (int b = 0; b < 4; b++) if (sv[k][b]) exp[8*b +: 8] = 8'h00;
      rd_exp(32'h0000_0100, exp, 1'b0, $sformatf("SRAM after WSTRB %b", sv[k]));
    end
  endtask

  task automatic test_sram_b2b();
    $display("-- BUS-07 back-to-back SRAM reads");
    item("BUS-07");
    for (int i = 0; i < 8; i++) wr(32'h0000_0200 + 4 * i, 32'h5000_0000 + i * 32'h0101_0101, 4'hF, 1'b0, "fill");
    for (int i = 0; i < 8; i++) begin
      cpu(1'b0, 1'b0, 32'h0000_0200 + 4 * ((i * 3) % 8), 32'h0, 4'h0, rdv, errv, i != 7);
      check(rdv == 32'h5000_0000 + ((i * 3) % 8) * 32'h0101_0101 && !errv,
            $sformatf("back-to-back read %0d: 0x%08h", i, rdv));
    end
  endtask

  task automatic test_bridge_protocol();
    $display("-- BUS-09 APB SETUP / ACCESS, BUS-10 PSTRB / PPROT");
    item("BUS-09");
    nlog = apb_log.size();
    wr(32'h1000_0040, 32'h1357_9BDF, 4'hF, 1'b0, "slot 0 write");
    rd_exp(32'h1000_0040, 32'h1357_9BDF, 1'b0, "slot 0 read");
    check(apb_log.size() == nlog + 2, "one APB transfer per AXI transfer");
    item("BUS-10");
    wr(32'h1000_0044, 32'hFFFF_FFFF, 4'hF, 1'b0, "PSTRB 1111");
    check(apb_log[$].strb == 4'hF && apb_log[$].prot == 3'b001,
          $sformatf("write WSTRB 1111: PSTRB %b PPROT %b", apb_log[$].strb, apb_log[$].prot));
    wr(32'h1000_0044, 32'h0000_0000, 4'b0001, 1'b0, "PSTRB 0001");
    check(apb_log[$].strb == 4'b0001, $sformatf("write WSTRB 0001: PSTRB %b", apb_log[$].strb));
    rd_exp(32'h1000_0044, 32'hFFFF_FF00, 1'b0, "after PSTRB 0001");
    check(apb_log[$].strb == 4'b0000 && !apb_log[$].wr && apb_log[$].prot == 3'b001,
          $sformatf("read: PSTRB %b PPROT %b, expected 0000 / 001", apb_log[$].strb, apb_log[$].prot));
    item("BUS-16");
    cpu(1'b0, 1'b1, 32'h1000_0044, 32'h0, 4'h0, rdv, errv);
    check(apb_log[$].prot == 3'b101, $sformatf("instruction fetch: PPROT %b, expected 101", apb_log[$].prot));
  endtask

  task automatic test_wait_states();
    int ws[4];
    $display("-- BUS-11 APB wait states");
    item("BUS-11");
    ws = '{0, 1, 2, 5};
    foreach (ws[k]) begin
      wait_n[0] = ws[k];
      wr(32'h1000_0080, 32'hC0DE_0000 + ws[k], 4'hF, 1'b0, $sformatf("%0d wait states", ws[k]));
      check(apb_log[$].waits == ws[k], $sformatf("write: %0d wait cycles seen, expected %0d", apb_log[$].waits, ws[k]));
      rd_exp(32'h1000_0080, 32'hC0DE_0000 + ws[k], 1'b0, $sformatf("%0d wait states", ws[k]));
      check(apb_log[$].waits == ws[k], $sformatf("read: %0d wait cycles seen, expected %0d", apb_log[$].waits, ws[k]));
    end
    wait_n[0] = 0;
  endtask

  task automatic test_pslverr();
    $display("-- BUS-12 PSLVERR");
    item("BUS-12");
    err_rd[3] = 1'b1;
    err_wr[3] = 1'b1;
    cpu(1'b0, 1'b0, 32'h1000_3010, 32'h0, 4'h0, rdv, errv);
    check(errv == 1'b1 && last_rresp == SLVERR, $sformatf("PSLVERR on read: mem_err %b RRESP %b", errv, last_rresp));
    cpu(1'b1, 1'b0, 32'h1000_3010, 32'h1, 4'hF, rdv, errv);
    check(errv == 1'b1 && last_bresp == SLVERR, $sformatf("PSLVERR on write: mem_err %b BRESP %b", errv, last_bresp));
    err_rd[3] = 1'b0;
    err_wr[3] = 1'b0;
    wr(32'h1000_3010, 32'h0000_0077, 4'hF, 1'b0, "slot 3 after PSLVERR");
    check(last_bresp == OKAY, "OKAY again after PSLVERR");
  endtask

  task automatic test_order();
    logic [1:0]  br;
    logic [31:0] rdat;
    $display("-- BUS-13 write and read in the same cycle");
    item("BUS-13");
    amem[0][8] = 32'h0BAD_F00D;                       // APB offset 0x020
    nlog = apb_log.size();
    direct = 1'b1;
    @(posedge clk); #1;
    d_awaddr = 32'h1000_0010; d_awvalid = 1'b1;
    d_wdata  = 32'h600D_CAFE; d_wstrb = 4'hF; d_wvalid = 1'b1;
    d_araddr = 32'h1000_0020; d_arvalid = 1'b1;
    d_bready = 1'b1; d_rready = 1'b1;
    fork
      begin
        do @(posedge clk); while (!x_awready);
        #1 d_awvalid = 1'b0;
      end
      begin
        do @(posedge clk); while (!x_wready);
        #1 d_wvalid = 1'b0;
      end
      begin
        do @(posedge clk); while (!x_arready);
        #1 d_arvalid = 1'b0;
      end
      begin
        do @(posedge clk); while (!x_bvalid);
        br = x_bresp;
      end
      begin
        do @(posedge clk); while (!x_rvalid);
        rdat = x_rdata;
      end
    join
    @(posedge clk); #1;
    d_bready = 1'b0; d_rready = 1'b0;
    direct = 1'b0;
    check(apb_log.size() == nlog + 2, $sformatf("%0d APB transfers, expected 2", apb_log.size() - nlog));
    if (apb_log.size() == nlog + 2) begin
      check(apb_log[nlog].wr && apb_log[nlog].addr == 12'h010, "first APB transfer is not the write");
      check(!apb_log[nlog + 1].wr && apb_log[nlog + 1].addr == 12'h020, "second APB transfer is not the read");
    end
    check(br == OKAY && rdat == 32'h0BAD_F00D, $sformatf("BRESP %b, read data %h", br, rdat));
    rd_exp(32'h1000_0010, 32'h600D_CAFE, 1'b0, "write data after the same-cycle case");
  endtask

  task automatic test_master2();
    logic [1:0] rs[4];
    $display("-- BUS-14 / 15 / 16 master adapter against a slave with random delays");
    rs = '{OKAY, EXOKAY, SLVERR, DECERR};
    item("BUS-14");
    for (int i = 0; i < 40; i++) begin
      logic [31:0] a;
      a = 32'h2000_0000 + 4 * i;
      s2_resp = OKAY;
      cpu2(1'b1, 1'b0, a, ~a, 4'(i), rdv, errv);
      check(s2_last_awaddr == a && s2_last_wdata == ~a && s2_last_wstrb == 4'(i),
            $sformatf("write %0d: slave saw %h / %h / %b", i, s2_last_awaddr, s2_last_wdata, s2_last_wstrb));
      cpu2(1'b0, 1'b0, a, 32'h0, 4'h0, rdv, errv);
      check(s2_last_araddr == a && rdv == ~a, $sformatf("read %0d: slave saw %h, data %h", i, s2_last_araddr, rdv));
    end
    item("BUS-15");
    foreach (rs[k]) begin
      s2_resp = rs[k];
      cpu2(1'b0, 1'b0, 32'h3000_0000, 32'h0, 4'h0, rdv, errv);
      check(errv == rs[k][1], $sformatf("read RRESP %b: mem_err %b", rs[k], errv));
      cpu2(1'b1, 1'b0, 32'h3000_0000, 32'h0, 4'hF, rdv, errv);
      check(errv == rs[k][1], $sformatf("write BRESP %b: mem_err %b", rs[k], errv));
    end
    s2_resp = OKAY;
    // main path: OKAY, SLVERR (disabled slot), DECERR (unmapped)
    rd_exp(32'h0000_0000, 32'h0123_4567, 1'b0, "OKAY on the main path");
    rd_exp(32'h1000_7000, 32'h0, 1'b1, "SLVERR on the main path");
    rd_exp(32'h0000_4000, 32'h0, 1'b1, "DECERR on the main path");
    item("BUS-16");
    cpu2(1'b0, 1'b1, 32'h0000_0100, 32'h0, 4'h0, rdv, errv);
    check(s2_last_arprot == 3'b101, $sformatf("fetch: ARPROT %b, expected 101", s2_last_arprot));
    cpu2(1'b0, 1'b0, 32'h0000_0104, 32'h0, 4'h0, rdv, errv);
    check(s2_last_arprot == 3'b001, $sformatf("data load: ARPROT %b, expected 001", s2_last_arprot));
    cpu2(1'b1, 1'b0, 32'h0000_0108, 32'h0, 4'hF, rdv, errv);
    check(s2_last_awprot == 3'b001, $sformatf("data store: AWPROT %b, expected 001", s2_last_awprot));
  endtask

  // ================================================================ main
  initial begin
    for (int s = 0; s < 16; s++) begin
      wait_n[s] = 0; err_rd[s] = 1'b0; err_wr[s] = 1'b0; prd_q[s] = 32'h0;
      for (int w = 0; w < 1024; w++) amem[s][w] = 32'h0;
    end
    $display("tb_bus_sys: start");
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;
    repeat (2) @(posedge clk);

    test_init_file();                              // BUS-08 (before any write)
    test_sram_decode();                            // BUS-01
    $display("-- BUS-02 / BUS-03 unmapped addresses");
    unmapped("BUS-02", 32'h0000_4000);
    unmapped("BUS-02", 32'h0FFF_FFFC);
    unmapped("BUS-03", 32'h1001_0000);
    unmapped("BUS-03", 32'hFFFF_FFFC);
    test_apb_slots();                              // BUS-04, 05
    test_sram_strobes();                           // BUS-06
    test_sram_b2b();                               // BUS-07
    test_bridge_protocol();                        // BUS-09, 10, 16
    test_wait_states();                            // BUS-11
    test_pslverr();                                // BUS-12
    test_order();                                  // BUS-13
    test_master2();                                // BUS-14, 15, 16

    repeat (5) @(posedge clk);
    vplan_pkg::report(VP_BLOCK, VP_N, "BUS-17");
    $finish;
  end

  initial begin
    #5ms;
    $display("ERROR: timeout");
    $display("TEST FAILED");
    $finish;
  end

endmodule
