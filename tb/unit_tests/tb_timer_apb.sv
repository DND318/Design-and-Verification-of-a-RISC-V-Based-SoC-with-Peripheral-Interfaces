// Directed, self-checking testbench for timer_apb.
// Expected values come from the register map (regmap.py TIMER) and the spec
// text, measured only through the APB port and irq_mtip_o, using a free-running
// clock-cycle counter of the testbench as time reference.
// Checks are grouped by vplan item (doc/vplan, sheet TIMER); the log ends
// with a PASS / FAIL / NOT RUN line per item, then "TEST PASSED" or
// "TEST FAILED" for scripts/check_log.sh.
`timescale 1ns/1ps
module tb_timer_apb;

  localparam logic [11:0] TCR   = 12'h000;
  localparam logic [11:0] TIER  = 12'h004;
  localparam logic [11:0] TISR  = 12'h008;
  localparam logic [11:0] TDR0  = 12'h010;
  localparam logic [11:0] TDR1  = 12'h014;
  localparam logic [11:0] TCMP0 = 12'h018;
  localparam logic [11:0] TCMP1 = 12'h01C;

  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic        psel = 1'b0;
  logic        penable = 1'b0;
  logic        pwrite = 1'b0;
  logic [11:0] paddr = 12'h0;
  logic [31:0] pwdata = 32'h0;
  logic [3:0]  pstrb = 4'h0;
  logic [31:0] prdata;
  logic        pready, pslverr;
  logic        irq_mtip;

  longint unsigned cyc = 0;      // number of rising edges since time 0
  longint unsigned cyc_wr = 0;   // edge number of the last APB write (access edge)
  longint unsigned cyc_rd = 0;   // value of cyc while the last APB read was sampled

  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  timer_apb dut (
    .clk_i(clk), .rst_ni(rst_n),
    .psel_i(psel), .penable_i(penable), .pwrite_i(pwrite), .paddr_i(paddr),
    .pwdata_i(pwdata), .pstrb_i(pstrb), .prdata_o(prdata), .pready_o(pready),
    .pslverr_o(pslverr), .irq_mtip_o(irq_mtip)
  );

  initial begin
    #20_000_000;
    $display("ERROR: timeout");
    $display("TEST FAILED");
    $finish;
  end

  // ------------------------------------------------------------ APB driver
  // SETUP then ACCESS; signals change 1 ns after a rising edge.
  task automatic apb_write(input logic [11:0] addr, input logic [31:0] data,
                           input logic [3:0] strb = 4'hF);
    @(posedge clk); #1;
    psel = 1'b1; penable = 1'b0; pwrite = 1'b1; paddr = addr; pwdata = data; pstrb = strb;
    @(posedge clk); #1;
    penable = 1'b1;
    @(negedge clk);
    check(pready === 1'b1 && pslverr === 1'b0, $sformatf("write %h: pready=%b pslverr=%b", addr, pready, pslverr));
    @(posedge clk);
    cyc_wr = cyc + 1;  // cyc is incremented by this edge (NBA)
    #1;
    psel = 1'b0; penable = 1'b0; pwrite = 1'b0; pstrb = 4'h0;
  endtask

  task automatic apb_read(input logic [11:0] addr, output logic [31:0] data);
    @(posedge clk); #1;
    psel = 1'b1; penable = 1'b0; pwrite = 1'b0; paddr = addr; pstrb = 4'h0;
    @(posedge clk); #1;
    penable = 1'b1;
    @(negedge clk);
    data   = prdata;
    cyc_rd = cyc;
    check(pready === 1'b1 && pslverr === 1'b0, $sformatf("read %h: pready=%b pslverr=%b", addr, pready, pslverr));
    @(posedge clk); #1;
    psel = 1'b0; penable = 1'b0;
  endtask

`define TB_OWN_APB
`include "apb_common.svh"
`include "vplan/vp_timer.svh"

  task automatic expect_reg(input logic [11:0] addr, input logic [31:0] exp, input string what);
    logic [31:0] d;
    apb_read(addr, d);
    check(d === exp, $sformatf("%s: read %h = %h, expected %h", what, addr, d, exp));
  endtask

  task automatic idle(input int n);
    repeat (n) @(posedge clk);
    #1;
  endtask

  function automatic logic [31:0] merge(input logic [31:0] o, input logic [31:0] n, input logic [3:0] s);
    for (int b = 0; b < 4; b++) if (s[b]) o[8*b +: 8] = n[8*b +: 8];
    return o;
  endfunction

  // Timer must be stopped. Load the 64-bit counter.
  task automatic set_cnt(input logic [63:0] v);
    apb_write(TDR0, v[31:0]);
    apb_write(TDR1, v[63:32]);
  endtask

  task automatic set_cmp(input logic [63:0] v);
    apb_write(TCMP1, v[63:32]);
    apb_write(TCMP0, v[31:0]);
  endtask

  task automatic read_cnt(output logic [63:0] v);
    logic [31:0] lo, hi;
    apb_read(TDR0, lo);
    apb_read(TDR1, hi);
    v = {hi, lo};
  endtask

  // ------------------------------------------------------------ tests
  task automatic test_reset_values();
    $display("-- reset values");
    expect_reg(TCR,   32'h0000_0100, "TCR reset");
    expect_reg(TIER,  32'h0000_0000, "TIER reset");
    expect_reg(TISR,  32'h0000_0000, "TISR reset");
    expect_reg(TDR0,  32'h0000_0000, "TDR0 reset");
    expect_reg(TDR1,  32'h0000_0000, "TDR1 reset");
    expect_reg(TCMP0, 32'hFFFF_FFFF, "TCMP0 reset");
    expect_reg(TCMP1, 32'hFFFF_FFFF, "TCMP1 reset");
    check(irq_mtip === 1'b0, "irq_mtip after reset");
    // Counter does not run after reset (timer_en = 0)
    idle(50);
    expect_reg(TDR0,  32'h0000_0000, "TDR0 holds while timer_en=0");
  endtask

  task automatic test_reserved();
    logic [11:0] ofs [5] = '{12'h00C, 12'h020, 12'h024, 12'h800, 12'hFFC};
    $display("-- reserved bits and offsets");
    // Reserved offsets read 0, writes ignored and do not disturb registers
    foreach (ofs[i]) begin
      apb_write(ofs[i], 32'hFFFF_FFFF);
      expect_reg(ofs[i], 32'h0, $sformatf("reserved offset %h", ofs[i]));
    end
    expect_reg(TCR,   32'h0000_0100, "TCR after reserved writes");
    expect_reg(TCMP0, 32'hFFFF_FFFF, "TCMP0 after reserved writes");
    expect_reg(TDR0,  32'h0, "TDR0 after reserved writes");
    // Reserved bits of TCR / TIER read 0 (div_val=8 legal, timer_en=0)
    apb_write(TCR, 32'hFFFF_F8FE);
    expect_reg(TCR, 32'h0000_0802, "TCR reserved bits");
    apb_write(TIER, 32'hFFFF_FFFF);
    expect_reg(TIER, 32'h0000_0001, "TIER reserved bits");
    apb_write(TIER, 32'h0);
    expect_reg(TIER, 32'h0, "TIER cleared");
    // TISR is read-only
    apb_write(TISR, 32'hFFFF_FFFF);
    expect_reg(TISR, 32'h0, "TISR write ignored");
    // Unaligned address bits [1:0] are don't care
    expect_reg(TCR | 12'h3, 32'h0000_0802, "TCR at offset 0x03");
    apb_write(TCR, 32'h0000_0100);
  endtask

  task automatic test_prohibited_div_val();
    $display("-- prohibited div_val");
    apb_write(TCR, 32'h0000_0500);           // div_val = 5
    expect_reg(TCR, 32'h0000_0500, "TCR div_val=5");
    for (int v = 9; v < 16; v++) begin
      // Prohibited div_val: div_val unchanged, div_en still written
      apb_write(TCR, (v << 8) | 32'h2);
      expect_reg(TCR, 32'h0000_0502, $sformatf("prohibited div_val=%0d with div_en=1", v));
      apb_write(TCR, (v << 8));
      expect_reg(TCR, 32'h0000_0500, $sformatf("prohibited div_val=%0d with div_en=0", v));
    end
    for (int v = 0; v < 9; v++) begin
      apb_write(TCR, (v << 8));
      expect_reg(TCR, v << 8, $sformatf("legal div_val=%0d", v));
    end
    apb_write(TCR, 32'h0000_0100);
  endtask

  task automatic test_strobes();
    logic [11:0] regs [4] = '{TDR0, TDR1, TCMP0, TCMP1};
    logic [31:0] model;
    $display("-- byte strobes");
    foreach (regs[i]) begin
      apb_write(regs[i], 32'hA5A5_5A5A);
      model = 32'hA5A5_5A5A;
      for (int s = 0; s < 16; s++) begin
        logic [31:0] d = {4{8'(s * 17 + i)}} ^ 32'h0F1E_2D3C;
        apb_write(regs[i], d, 4'(s));
        model = merge(model, d, 4'(s));
        expect_reg(regs[i], model, $sformatf("reg %h strobe %b", regs[i], 4'(s)));
      end
    end
    // TCR: byte 0 = div_en/timer_en, byte 1 = div_val
    apb_write(TCR, 32'h0000_0100);
    apb_write(TCR, 32'h0000_0602, 4'b0001);   // only byte 0
    expect_reg(TCR, 32'h0000_0102, "TCR strobe 0001");
    apb_write(TCR, 32'h0000_0600, 4'b0010);   // only byte 1
    expect_reg(TCR, 32'h0000_0602, "TCR strobe 0010");
    apb_write(TCR, 32'h0000_0301, 4'b1100);   // no byte holding a field
    expect_reg(TCR, 32'h0000_0602, "TCR strobe 1100");
    apb_write(TCR, 32'h0000_0000, 4'b0000);
    expect_reg(TCR, 32'h0000_0602, "TCR strobe 0000");
    apb_write(TIER, 32'h1, 4'b1110);
    expect_reg(TIER, 32'h0, "TIER strobe 1110");
    apb_write(TIER, 32'h1, 4'b0001);
    expect_reg(TIER, 32'h1, "TIER strobe 0001");
    apb_write(TIER, 32'h0);
    apb_write(TCR, 32'h0000_0100);
    set_cnt(64'h0);
    set_cmp({64{1'b1}});
  endtask

  // Rate check: over a window that is a multiple of the period P, the counter
  // must advance by exactly window/P, whatever the prescaler phase.
  task automatic measure_rate(input logic [31:0] tcr, input int unsigned period, input string what);
    logic [31:0] v0, v1, v2;
    longint unsigned c0, c1, c2;
    int unsigned m;
    apb_write(TCR, tcr & 32'hFFFF_FFFE);      // stop, set divider
    set_cnt(64'h0);
    apb_write(TCR, tcr | 32'h1);              // start
    idle(3 * period + 5);
    for (int k = 0; k < 2; k++) begin
      m = (period == 1) ? 200 : (period < 16 ? 400 / period : 8);
      apb_read(TDR0, v0); c0 = cyc_rd;
      idle(m * period - 3);
      apb_read(TDR0, v1); c1 = cyc_rd;
      check(c1 - c0 == m * period, $sformatf("%s: tb window %0d", what, c1 - c0));
      check(v1 - v0 == m, $sformatf("%s: %0d ticks in %0d clocks, expected %0d (period %0d)",
                                    what, v1 - v0, c1 - c0, m, period));
      // A window one clock longer/shorter than m*P sees m or m+1 / m-1 or m ticks
      if (period > 2) begin
        idle(period - 2);
        apb_read(TDR0, v2); c2 = cyc_rd;
        check(v2 - v1 >= 1 && v2 - v1 <= 2, $sformatf("%s: %0d ticks in %0d clocks", what, v2 - v1, c2 - c1));
      end
    end
    // Stopping holds the value
    apb_write(TCR, tcr & 32'hFFFF_FFFE);
    apb_read(TDR0, v0);
    idle(2 * period + 10);
    apb_read(TDR0, v1);
    check(v1 == v0, $sformatf("%s: counter moved while timer_en=0 (%0d -> %0d)", what, v0, v1));
    $display("   %s: period %0d clocks OK", what, period);
  endtask

  task automatic test_divider();
    $display("-- divider");
    measure_rate(32'h0000_0000, 1,   "div_en=0 div_val=0");
    measure_rate(32'h0000_0800, 1,   "div_en=0 div_val=8");
    for (int v = 0; v <= 8; v++)
      measure_rate((v << 8) | 32'h2, 1 << v, $sformatf("div_en=1 div_val=%0d", v));
    // div_val = 1 from reset, only byte 0 written: divide by 2
    apb_write(TCR, 32'h0000_0100);
    measure_rate(32'h0000_0102, 2, "div_val=1 (reset) strobe 0001");
    // Prohibited value while configuring keeps the previous divider (16)
    apb_write(TCR, 32'h0000_0402);
    apb_write(TCR, 32'h0000_0C02);
    expect_reg(TCR, 32'h0000_0402, "TCR after prohibited 12");
    measure_rate(32'h0000_0402, 16, "div_val=4 kept after prohibited 12");
    apb_write(TCR, 32'h0000_0100);
  endtask

  // Exact count over a known number of enabled clocks (div_en = 0):
  // timer_en is 1 from the edge after the start write up to and including the
  // stop-write edge, so ticks = cyc(stop) - cyc(start).
  task automatic run_clocks(input int n, output longint unsigned ticks);
    longint unsigned cs;
    apb_write(TCR, 32'h0000_0001);
    cs = cyc_wr;
    idle(n);
    apb_write(TCR, 32'h0000_0000);
    ticks = cyc_wr - cs;
  endtask

  task automatic test_carry();
    logic [63:0] v, start;
    longint unsigned t;
    $display("-- 64-bit carry");
    item("TIMER-25");
    start = 64'h1234_5678_FFFF_FFF0;
    set_cnt(start);
    run_clocks(30, t);
    read_cnt(v);
    check(v == start + t, $sformatf("carry TDR0->TDR1: %h expected %h", v, start + t));
    check(v[63:32] == 32'h1234_5679, $sformatf("TDR1 after carry = %h", v[63:32]));
    item("TIMER-26");
    start = 64'hFFFF_FFFF_FFFF_FFF8;
    set_cnt(start);
    run_clocks(20, t);
    read_cnt(v);
    check(v == start + t, $sformatf("64-bit wrap: %h expected %h", v, start + t));
    check(v[63:32] == 32'h0, "64-bit wrap TDR1 = 0");
    // Carry with the prescaler: div_val=2 (P=4), long run, exact window
    item("TIMER-25");
    set_cnt(64'h0000_0000_FFFF_FFFE);
    apb_write(TCR, 32'h0000_0203);
    idle(40);
    apb_write(TCR, 32'h0000_0202);
    read_cnt(v);
    check(v >= 64'h1_0000_0008 && v <= 64'h1_0000_000C, $sformatf("carry with prescaler: %h", v));
    apb_write(TCR, 32'h0000_0100);
  endtask

  task automatic test_write_wins();
    logic [31:0] d, lo, hi, e;
    logic [63:0] v;
    longint unsigned cw, cs, c0;
    $display("-- software write wins over increment");
    set_cnt(64'h0);
    apb_write(TCR, 32'h0000_0001);       // count every clock
    idle(10);
    apb_write(TDR0, 32'h0000_1000);      // written at the access edge, no increment there
    cw = cyc_wr;
    apb_read(TDR0, d);
    cs = cyc_rd;
    e = 32'h1000 + 32'(cs - cw);
    check(d == e, $sformatf("TDR0 write while running: %h expected %h", d, e));
    // Byte-strobe write while running: written byte replaced, others hold
    apb_write(TCR, 32'h0000_0000);
    set_cnt(64'h0000_0007_1234_5610);
    apb_write(TCR, 32'h0000_0001);
    c0 = cyc_wr;
    apb_write(TDR0, 32'h00AB_0000, 4'b0100);
    cw = cyc_wr;
    apb_read(TDR0, d);
    cs = cyc_rd;
    // increments on edges c0+1 .. cw-1, none at the write edge cw, then one
    // per edge up to the sample
    e = merge(32'h1234_5610 + 32'(cw - 1 - c0), 32'h00AB_0000, 4'b0100) + 32'(cs - cw);
    check(d == e, $sformatf("TDR0 byte-2 write while running: %h expected %h", d, e));
    // TDR1 write while running: whole counter held in that cycle
    apb_write(TCR, 32'h0000_0000);
    set_cnt(64'h0000_0000_0000_0000);
    apb_write(TCR, 32'h0000_0001);
    cs = cyc_wr;
    idle(5);
    apb_write(TDR1, 32'h0000_0055);
    cw = cyc_wr;
    apb_write(TCR, 32'h0000_0000);
    read_cnt(v);
    {hi, lo} = v;
    check(hi == 32'h55, $sformatf("TDR1 written while running: %h", hi));
    // ticks on edges cs+1 .. stop edge, minus the TDR1 write edge
    check(lo == 32'((cyc_wr - cs) - 1), $sformatf("TDR0 during TDR1 write: %0d expected %0d", lo, (cyc_wr - cs) - 1));
    apb_write(TCR, 32'h0000_0100);
  endtask

  task automatic test_compare();
    logic [63:0] v;
    longint unsigned cs, ci;
    $display("-- compare match and irq");
    item("TIMER-28");
    apb_write(TCR, 32'h0000_0100);
    apb_write(TIER, 32'h0);
    set_cnt(64'd0);
    set_cmp(64'd100);
    expect_reg(TISR, 32'h0, "cnt 0 < cmp 100");
    apb_write(TDR0, 32'd99);
    expect_reg(TISR, 32'h0, "cnt 99 < cmp 100");
    apb_write(TDR0, 32'd100);
    expect_reg(TISR, 32'h1, "cnt 100 == cmp 100");
    item("TIMER-31");
    idle(3);
    check(irq_mtip === 1'b0, "irq gated by cmp_ie=0");
    apb_write(TIER, 32'h1);
    idle(2);
    check(irq_mtip === 1'b1, "irq with cmp_ie=1 and match");
    apb_write(TIER, 32'h0);
    idle(2);
    check(irq_mtip === 1'b0, "irq low after cmp_ie=0");
    expect_reg(TISR, 32'h1, "cmp_match still 1 with cmp_ie=0");
    apb_write(TIER, 32'h1);
    // Clearing by writing a larger compare value
    item("TIMER-32");
    apb_write(TCMP0, 32'd200);
    idle(2);
    check(irq_mtip === 1'b0, "irq low after TCMP0 = 200");
    expect_reg(TISR, 32'h0, "cmp_match cleared by larger TCMP0");
    apb_write(TDR0, 32'd201);
    expect_reg(TISR, 32'h1, "cnt 201 > cmp 200");
    idle(1);
    check(irq_mtip === 1'b1, "irq at cnt 201");
    // 64-bit compare: high word dominates
    item("TIMER-29");
    set_cmp(64'h0000_0001_0000_0000);
    idle(2);
    check(irq_mtip === 1'b0, "irq low after TCMP = 1_00000000");
    set_cnt(64'h0000_0000_FFFF_FFFF);
    expect_reg(TISR, 32'h0, "0_FFFFFFFF < 1_00000000");
    set_cnt(64'h0000_0001_0000_0000);
    expect_reg(TISR, 32'h1, "1_00000000 >= 1_00000000");
    set_cmp(64'h0000_0001_FFFF_FFFF);
    expect_reg(TISR, 32'h0, "1_00000000 < 1_FFFFFFFF");
    set_cnt(64'h0000_0002_0000_0000);
    expect_reg(TISR, 32'h1, "2_00000000 >= 1_FFFFFFFF");
    // Unsigned: bit 63 set is larger
    item("TIMER-28");
    set_cmp(64'h7FFF_FFFF_FFFF_FFFF);
    set_cnt(64'h8000_0000_0000_0000);
    expect_reg(TISR, 32'h1, "unsigned 80.. >= 7F..");
    set_cnt(64'h7FFF_FFFF_FFFF_FFFE);
    expect_reg(TISR, 32'h0, "7F..FE < 7F..FF");
    // Reset compare all-ones: counter all-ones is the only match
    set_cmp({64{1'b1}});
    set_cnt({64{1'b1}});
    expect_reg(TISR, 32'h1, "all-ones >= all-ones");
    set_cnt(64'h0);
    expect_reg(TISR, 32'h0, "0 < all-ones");
    idle(2);
    check(irq_mtip === 1'b0, "irq low with cnt 0");

    // Running timer reaches the compare value: irq latency
    set_cnt(64'd1000);
    set_cmp(64'd1050);
    apb_write(TCR, 32'h0000_0001);   // every clock
    cs = cyc_wr;                     // after edge cs+k the counter is 1000+k
    ci = 0;
    for (int i = 0; i < 200 && ci == 0; i++) begin
      @(posedge clk); #1;
      if (irq_mtip === 1'b1) ci = cyc;
    end
    check(ci != 0, "irq never rose while counting to TCMP");
    // counter reaches 1050 after edge cs+50; registered irq is High after edge cs+51
    check(ci == cs + 51, $sformatf("irq rose after edge %0d, expected %0d (1 clock latency)", ci - cs, 51));
    expect_reg(TISR, 32'h1, "cmp_match while running past TCMP");
    // Clear while running: write a larger compare (high word first)
    item("TIMER-32");
    apb_write(TCMP1, 32'h0000_0001);
    idle(2);
    check(irq_mtip === 1'b0, "irq low after TCMP1 = 1 while running");
    expect_reg(TISR, 32'h0, "cmp_match 0 after larger TCMP1");
    apb_write(TCR, 32'h0000_0000);
    item("TIMER-24");
    // Disabling the timer does not clear the counter (advanced item not built)
    read_cnt(v);
    check(v > 64'd1050 && v < 64'd2000, $sformatf("counter kept after timer_en=0: %h", v));
    apb_write(TIER, 32'h0);
    set_cmp({64{1'b1}});
    apb_write(TCR, 32'h0000_0100);
  endtask

  // TIMER-24: counter holds while timer_en = 0
  task automatic test_hold();
    logic [31:0] v0, v1;
    $display("-- timer_en = 0 holds");
    item("TIMER-24");
    set_cnt(64'h0);
    apb_write(TCR, 32'h0000_0001);
    idle(20);
    apb_write(TCR, 32'h0000_0000);
    apb_read(TDR0, v0);
    check(v0 != 0, "counter ran while timer_en = 1");
    idle(50);
    apb_read(TDR0, v1);
    check(v1 == v0, $sformatf("counter moved while timer_en = 0: %0d -> %0d", v0, v1));
    apb_write(TCR, 32'h0000_0100);
  endtask

  // TIMER-30: after reset no interrupt even with cmp_ie = 1 and counting
  task automatic test_no_irq_after_reset();
    $display("-- no irq after reset");
    apb_write(TIER, 32'h1);
    apb_write(TCR, 32'h0000_0001);
    for (int i = 0; i < 1000; i++) begin
      @(negedge clk);
      if (irq_mtip !== 1'b0) begin
        check(1'b0, "irq_mtip rose after reset (TCMP must reset to all ones)");
        break;
      end
    end
    expect_reg(TISR, 32'h0, "cmp_match 0 after reset");
    apb_write(TCR, 32'h0000_0000);
    apb_write(TIER, 32'h0);
    set_cnt(64'h0);
    apb_write(TCR, 32'h0000_0100);
  endtask

  initial begin
    $display("tb_timer_apb start");
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;
    vp_regs();                                   // TIMER-01 .. TIMER-20
    item("TIMER-15"); test_reserved();           // extra reserved-bit checks
    item("TIMER-20"); test_strobes();            // strobes on every register
    item("TIMER-23"); test_prohibited_div_val();
    item("TIMER-21");
    measure_rate(32'h0000_0000, 1, "div_en=0 div_val=0");
    measure_rate(32'h0000_0800, 1, "div_en=0 div_val=8");
    item("TIMER-22");
    for (int v = 0; v <= 8; v++)
      measure_rate((v << 8) | 32'h2, 1 << v, $sformatf("div_en=1 div_val=%0d", v));
    apb_write(TCR, 32'h0000_0100);
    measure_rate(32'h0000_0102, 2, "div_val=1 (reset) strobe 0001");
    item("TIMER-23");
    apb_write(TCR, 32'h0000_0402);
    apb_write(TCR, 32'h0000_0C02);
    expect_reg(TCR, 32'h0000_0402, "TCR after prohibited 12");
    measure_rate(32'h0000_0402, 16, "div_val=4 kept after prohibited 12");
    apb_write(TCR, 32'h0000_0100);
    test_hold();                                 // TIMER-24
    test_carry();                                // TIMER-25, 26
    item("TIMER-27"); test_write_wins();
    test_compare();                              // TIMER-28, 29, 31, 32, 24
    // Asynchronous reset in the middle of operation restores reset values
    item("TIMER-30");
    set_cnt(64'h1111_2222_3333_4444);
    apb_write(TIER, 32'h1);
    apb_write(TCR, 32'h0000_0503);
    idle(5);
    #2 rst_n = 1'b0;
    #1 check(irq_mtip === 1'b0, "irq low in reset");
    idle(2);
    rst_n = 1'b1;
    test_reset_values();
    test_no_irq_after_reset();
    idle(2);
    vplan_pkg::report(VP_BLOCK, VP_N);
    $finish;
  end

endmodule
