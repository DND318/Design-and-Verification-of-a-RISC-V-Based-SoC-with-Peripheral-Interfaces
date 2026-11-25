// Bus base test
class bus_base_test;
  string           name = "bus_base_test";
  virtual cpu_if   cpu0_vif, cpu1_vif;
  virtual axi_if   axd_vif, ax0_vif, ax1_vif, ax2_vif;
  virtual apbm_if  apb_vif;
  bus_environment  env;
  bus_stimulus     stim;
  bus_scoreboard   sb;
  apb_slave        pslv;       // APB slave model (wait states, PSLVERR, memory)
  axi_slave        aslv;       // AXI slave model of the second master

  localparam bit [1:0] OKAY = 2'b00, EXOKAY = 2'b01, SLVERR = 2'b10, DECERR = 2'b11;

  `include "vplan/vp_bus.svh"

  function new();
  endfunction

  virtual function void build();
    env = new(cpu0_vif, cpu1_vif, axd_vif, ax0_vif, ax1_vif, ax2_vif, apb_vif);
    env.build();
    stim = env.stim;
    sb   = env.sb;
    pslv = env.pslv;
    aslv = env.aslv;
  endfunction

  virtual task run_scenario();
  endtask

  task run_test();
    $display("%0t: [%s] start", $time, name);
    build();
    env.run();
    wait (cpu0_vif.rst_n === 1'b1);
    clks(2);
    run_scenario();
    clks(5);
    flush();
    sb.final_check();
    sb.report();
    $display("%0t: [%s] End simulation", $time, name);
    vplan_pkg::report(VP_BLOCK, VP_N, "BUS-17", 1'b1);
    $finish;
  endtask

  // ---------------------------------------------------------------- helpers
  function void check(input bit ok, input string what);
    vplan_pkg::chk(ok, what);
  endfunction

  function void check_at(input string id, input bit ok, input string what);
    vplan_pkg::chk_at(id, ok, what);
  endfunction

  task flush();
    env.flush();
  endtask

  // New vplan item: let the scoreboard finish the previous one first
  task item(input string id);
    flush();
    vplan_pkg::item(id);
  endtask

  task clks(input int n);
    repeat (n) @(posedge cpu0_vif.clk);
    #1;
  endtask

  // One request on CPU port p (0: main path, 1: second master).
  // keep = 1: mem_req stays high, the next request follows back to back.
  task cpu(input int p, input bit we, input bit instr, input bit [31:0] a, input bit [31:0] wd,
           input bit [3:0] st, output bit [31:0] rd, output bit err, input bit keep = 1'b0);
    bus_packet pkt = new();
    pkt.kind  = BUS_CPU;
    pkt.port  = p;
    pkt.we    = we;
    pkt.instr = instr;
    pkt.addr  = a;
    pkt.wdata = wd;
    pkt.wstrb = st;
    pkt.keep  = keep;
    stim.send(pkt);
    check(pkt.n_ready != 0, $sformatf("CPU port %0d: no mem_ready for %s %h", p, we ? "write" : "read", a));
    check_at("BUS-15", pkt.n_ready <= 1, $sformatf("CPU port %0d: %0d mem_ready pulses for one request", p, pkt.n_ready));
    rd  = pkt.rdata;
    err = pkt.err;
  endtask

  // Write / read on the main path with the expected mem_err (and data)
  task wr(input bit [31:0] a, input bit [31:0] d, input bit [3:0] st, input bit exp_err, input string what);
    bit [31:0] r;
    bit        e;
    cpu(0, 1'b1, 1'b0, a, d, st, r, e);
    check(e == exp_err, $sformatf("%s: write %h mem_err = %b, expected %b", what, a, e, exp_err));
  endtask

  task rd_exp(input bit [31:0] a, input bit [31:0] exp, input bit exp_err, input string what);
    bit [31:0] r;
    bit        e;
    cpu(0, 1'b0, 1'b0, a, 32'h0, 4'h0, r, e);
    check(e == exp_err, $sformatf("%s: read %h mem_err = %b, expected %b", what, a, e, exp_err));
    if (!exp_err) check(r == exp, $sformatf("%s: read %h = %h, expected %h", what, a, r, exp));
  endtask

  // Write (AW + W) and read (AR) valid in the same cycle on the xbar input
  task direct(input bit [31:0] wa, input bit [31:0] wd, input bit [31:0] ra,
              output bit [1:0] bresp, output bit [1:0] rresp, output bit [31:0] rdata);
    bus_packet pkt = new();
    pkt.kind  = BUS_AXI;
    pkt.do_wr = 1'b1;
    pkt.do_rd = 1'b1;
    pkt.addr  = wa;
    pkt.wdata = wd;
    pkt.wstrb = 4'hF;
    pkt.raddr = ra;
    stim.send(pkt);
    bresp = pkt.bresp;
    rresp = pkt.rresp;
    rdata = pkt.rdata;
  endtask
endclass
