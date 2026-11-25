`timescale 1ns/1ps
// Directed, self-checking testbench for spi_apb (SPI master, APB slot 1).
// The SPI side is checked by an independent behavioural SPI slave model
// written from the SPI mode definitions (CPOL/CPHA, MSB/LSB first): it shifts
// out a known byte pattern on MISO (changing MISO a programmable delay after
// its shift edge), records the bytes it receives on MOSI, and checks SCLK
// half period, SCLK idle level, MOSI setup/hold around its sampling edge and
// that frames are 8 bits. It never looks inside the RTL.
// Checks are grouped by vplan item (doc/vplan, sheet SPI); the slave model
// counts its protocol checks against fixed items (SPI-24/26/27/29/32). The
// log ends with a PASS / FAIL / NOT RUN line per item, then "TEST PASSED" or
// "TEST FAILED" for scripts/check_log.sh.
module tb_spi_apb;

  localparam int TCLK = 20;   // 50 MHz

  // Register offsets (regmap.py SPI)
  localparam logic [11:0] A_CTRL   = 12'h000;
  localparam logic [11:0] A_CLKDIV = 12'h004;
  localparam logic [11:0] A_CS     = 12'h008;
  localparam logic [11:0] A_STATUS = 12'h00C;
  localparam logic [11:0] A_TXDATA = 12'h010;
  localparam logic [11:0] A_RXDATA = 12'h014;
  localparam logic [11:0] A_IER    = 12'h018;
  localparam logic [11:0] A_ISR    = 12'h01C;

  // STATUS bits
  localparam int ST_BUSY = 0, ST_TXFULL = 1, ST_TXEMPTY = 2, ST_RXFULL = 3, ST_RXEMPTY = 4;

  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic        psel = 1'b0, penable = 1'b0, pwrite = 1'b0;
  logic [11:0] paddr = 12'h0;
  logic [31:0] pwdata = 32'h0;
  logic [3:0]  pstrb = 4'h0;
  wire  [31:0] prdata;
  wire         pready, pslverr;
  wire         sclk, mosi, cs_n, irq;
  logic        miso = 1'b1;


  always #(TCLK/2) clk = ~clk;

  spi_apb dut (
    .clk_i(clk), .rst_ni(rst_n),
    .psel_i(psel), .penable_i(penable), .pwrite_i(pwrite), .paddr_i(paddr),
    .pwdata_i(pwdata), .pstrb_i(pstrb), .prdata_o(prdata),
    .pready_o(pready), .pslverr_o(pslverr),
    .spi_sclk_o(sclk), .spi_mosi_o(mosi), .spi_miso_i(miso),
    .spi_cs_no(cs_n), .irq_spi_o(irq)
  );

`include "apb_common.svh"
`include "vplan/vp_spi.svh"

  // ------------------------------------------------------------------ APB
  task automatic expect_reg(input logic [11:0] addr, input logic [31:0] exp, input string what);
    rd_check(addr, exp, what);
  endtask

  function automatic logic [31:0] ctrl_val(input bit en, input bit cpol, input bit cpha, input bit lsb);
    return {28'd0, lsb, cpha, cpol, en};
  endfunction

  // --------------------------------------------------------- SPI slave model
  bit         s_cpol, s_cpha, s_lsb;    // mode the slave is wired for
  int         s_half = 2 * TCLK;        // expected SCLK half period (ns)
  int         s_miso_dly = 1;           // MISO changes this long after the shift edge
  bit         s_check_b2b = 1'b0;       // check gap between frames is short
  logic [7:0] s_pat[$];                 // bytes the slave sends
  int         s_idx;
  logic [7:0] s_cur;
  logic [7:0] s_rx_sh;
  int         s_bit;                    // bits sampled in the current frame
  int         s_edge;                   // SCLK edges in the current frame (0..15)
  int         s_edges_total;
  logic [7:0] s_rx_q[$];                // bytes received on MOSI
  realtime    t_last_edge = -1.0;
  realtime    t_last_mosi = 0.0;
  realtime    t_last_sample = -1.0;

  function automatic logic frame_bit(input logic [7:0] b, input int n);
    return s_lsb ? b[n] : b[7-n];
  endfunction

  function automatic logic [7:0] next_pat();
    logic [7:0] b;
    b = (s_idx < s_pat.size()) ? s_pat[s_idx] : 8'h00;
    s_idx++;
    return b;
  endfunction

  task automatic drive_miso(input logic v);
    fork
      begin
        #(s_miso_dly);
        miso = v;
      end
    join_none
  endtask

  always @(negedge cs_n) begin
    if (rst_n) begin
    s_bit = 0;
    s_edge = 0;
    t_last_edge = -1.0;
    if (!s_cpha) begin
      // CPHA=0: first bit is put out on CS fall, before the first edge.
      // CPHA=1: it is put out on the first (shift) edge instead.
      s_cur = next_pat();
      drive_miso(frame_bit(s_cur, 0));
    end
    end
  end

  always @(posedge cs_n) begin
    if (rst_n) check_at("SPI-32", s_bit == 0 && s_edge == 0, $sformatf("slave: CS released inside a frame (bit %0d edge %0d)", s_bit, s_edge));
    drive_miso(1'b1);                                // released line, pull-up
  end

  always @(mosi) begin
    if (rst_n && cs_n === 1'b0) begin
      check_at("SPI-27", $realtime != t_last_sample, "slave: MOSI changed on the sampling edge (hold)");
      t_last_mosi = $realtime;
    end
  end

  always @(sclk) begin
    bit lead;
    if (rst_n && cs_n === 1'b0) begin
      lead = (sclk !== s_cpol);
      if (s_edge == 0) begin
        check_at("SPI-24", lead, $sformatf("slave: frame does not start with a leading edge (SCLK idle != CPOL %0d)", s_cpol));
        if (t_last_edge >= 0.0) begin
          check_at("SPI-26", $realtime - t_last_edge >= s_half,
                $sformatf("slave: gap between frames %0t < half period %0d", $realtime - t_last_edge, s_half));
          if (s_check_b2b)
            check_at("SPI-29", $realtime - t_last_edge <= s_half + 4 * TCLK,
                  $sformatf("slave: frames not back to back, gap %0t", $realtime - t_last_edge));
        end
      end else begin
        check_at("SPI-26", $realtime - t_last_edge == s_half,
              $sformatf("slave: SCLK half period %0t, expected %0d", $realtime - t_last_edge, s_half));
      end
      t_last_edge = $realtime;
      if (lead != s_cpha) begin
        // Sampling edge: CPHA=0 leading edge, CPHA=1 trailing edge.
        check_at("SPI-27", $realtime - t_last_mosi >= s_half,
              $sformatf("slave: MOSI setup %0t < half period", $realtime - t_last_mosi));
        t_last_sample = $realtime;
        if (s_lsb) s_rx_sh[s_bit] = mosi;
        else       s_rx_sh[7-s_bit] = mosi;
        s_bit++;
        if (s_bit == 8) begin
          s_rx_q.push_back(s_rx_sh);
          s_bit = 0;
        end
      end else begin
        // Shift edge: present the next bit (a new byte after a full frame).
        if (s_bit == 0) s_cur = next_pat();
        drive_miso(frame_bit(s_cur, s_bit));
      end
      s_edge = (s_edge + 1) % 16;
      s_edges_total++;
    end
  end

  int cs_edges = 0;                     // cs_n changes while a burst runs
  always @(cs_n) if (rst_n && s_check_b2b) cs_edges++;

  // ----------------------------------------------------------------- helpers
  function automatic logic [7:0] pat_byte(input int seed, input int k);
    logic [7:0] fixed [4];
    fixed = '{8'h01, 8'h80, 8'h3C, 8'hE6};
    if (k < 4) return fixed[k] ^ seed[7:0];
    return 8'((k * 8'h5B) + seed * 3) ^ 8'hA7;
  endfunction

  task automatic wait_status(input int bitn, input logic val, input int max_polls, input string what);
    logic [31:0] d;
    int n;
    n = 0;
    do begin
      apb_read(A_STATUS, d);
      n++;
    end while (d[bitn] !== val && n < max_polls);
    check(d[bitn] === val, $sformatf("timeout waiting for STATUS[%0d]=%b (%s)", bitn, val, what));
  endtask

  task automatic wait_done(input int max_polls, input string what);
    logic [31:0] d;
    int n;
    n = 0;
    do begin
      apb_read(A_ISR, d);
      n++;
    end while (d[0] !== 1'b1 && n < max_polls);
    check(d[0] === 1'b1, $sformatf("timeout waiting for ISR.done (%s), ISR=%h", what, d));
  endtask

  // Deselect, set the mode in DUT and slave, clear flags.
  task automatic setup_mode(input bit cpol, input bit cpha, input bit lsb, input int div, input int dly);
    apb_write(A_CS, 32'h1);
    apb_write(A_CTRL, ctrl_val(1'b0, cpol, cpha, lsb));
    apb_write(A_CLKDIV, div);
    apb_write(A_ISR, 32'h3);
    repeat (2) @(posedge clk);
    check(sclk === cpol, $sformatf("SCLK idle %b, expected CPOL %b", sclk, cpol));
    s_cpol = cpol; s_cpha = cpha; s_lsb = lsb;
    s_half = (div + 1) * TCLK;
    s_miso_dly = dly;
    s_rx_q.delete();
    s_idx = 0;
    s_edges_total = 0;
  endtask

  // One burst in the given mode, checked on both sides: tx goes out on MOSI,
  // the slave answers with sp on MISO.
  task automatic run_bytes(input bit cpol, input bit cpha, input bit lsb, input int div,
                           input logic [7:0] tx[$], input logic [7:0] sp[$], input int dly,
                           input bit enable_first);
    logic [31:0] d;
    string       tag;
    int          n;
    n = tx.size();
    tag = $sformatf("mode%0d lsb=%0d div=%0d n=%0d dly=%0d", {cpol, cpha}, lsb, div, n, dly);
    setup_mode(cpol, cpha, lsb, div, dly);
    s_pat = sp;
    s_check_b2b = 1'b1;
    apb_write(A_CS, 32'h0);
    check_at("SPI-32", cs_n === 1'b0, "cs_n pin not driven Low by CS=0");
    cs_edges = 0;
    if (enable_first) apb_write(A_CTRL, ctrl_val(1'b1, cpol, cpha, lsb));
    foreach (tx[k]) apb_write(A_TXDATA, {24'h0, tx[k]});
    if (!enable_first) apb_write(A_CTRL, ctrl_val(1'b1, cpol, cpha, lsb));
    wait_done(40 * n * (div + 2) + 50, tag);
    apb_read(A_STATUS, d);
    check(d[ST_BUSY] === 1'b0 && d[ST_TXEMPTY] === 1'b1, $sformatf("%s: STATUS %h after done", tag, d));
    check(d[ST_RXEMPTY] === 1'b0 && d[ST_RXFULL] === (n == 16), $sformatf("%s: STATUS %h rx flags", tag, d));
    check(s_rx_q.size() == n, $sformatf("%s: slave got %0d bytes, expected %0d", tag, s_rx_q.size(), n));
    check(s_edges_total == 16 * n, $sformatf("%s: %0d SCLK edges, expected %0d", tag, s_edges_total, 16 * n));
    check_at("SPI-32", cs_edges == 0, $sformatf("%s: cs_n changed %0d times during the burst", tag, cs_edges));
    for (int k = 0; k < n && k < s_rx_q.size(); k++)
      check(s_rx_q[k] === tx[k], $sformatf("%s: MOSI byte %0d = %h, expected %h", tag, k, s_rx_q[k], tx[k]));
    for (int k = 0; k < n; k++)
      expect_reg(A_RXDATA, {24'h0, sp[k]}, $sformatf("%s: RX byte %0d", tag, k));
    expect_reg(A_STATUS, 32'h14, {tag, ": STATUS idle"});
    check(sclk === cpol, $sformatf("%s: SCLK idle %b after burst", tag, sclk));
    s_check_b2b = 1'b0;
    apb_write(A_CTRL, ctrl_val(1'b0, cpol, cpha, lsb));
    apb_write(A_CS, 32'h1);
    check_at("SPI-32", cs_n === 1'b1, "cs_n pin not driven High by CS=1");
    apb_write(A_ISR, 32'h3);
  endtask

  // One burst of n generated bytes
  task automatic run_burst(input bit cpol, input bit cpha, input bit lsb, input int div,
                           input int n, input int dly, input bit enable_first, input int seed);
    logic [7:0] tx[$];
    logic [7:0] sp[$];
    tx.delete();
    sp.delete();
    for (int k = 0; k < n; k++) begin
      sp.push_back(pat_byte(seed + 17, k));
      tx.push_back(pat_byte(seed, k));
    end
    run_bytes(cpol, cpha, lsb, div, tx, sp, dly, enable_first);
  endtask

  // ------------------------------------------------------------------ tests
  task automatic test_reset_values();
    $display("-- reset values");
    item("SPI-01");
    expect_reg(A_CTRL,   32'h0000_0000, "CTRL reset");
    item("SPI-03");
    expect_reg(A_CLKDIV, 32'h0000_0001, "CLKDIV reset");
    item("SPI-05");
    expect_reg(A_CS,     32'h0000_0001, "CS reset");
    item("SPI-07");
    expect_reg(A_STATUS, 32'h0000_0014, "STATUS reset");
    item("SPI-09");
    expect_reg(A_TXDATA, 32'h0000_0000, "TXDATA reset");
    item("SPI-11");
    expect_reg(A_RXDATA, 32'h0000_0000, "RXDATA reset");
    item("SPI-13");
    expect_reg(A_IER,    32'h0000_0000, "IER reset");
    item("SPI-15");
    expect_reg(A_ISR,    32'h0000_0000, "ISR reset");
    item("SPI-16");
    expect_reg(12'h020,  32'h0, "reserved 0x020");
    expect_reg(12'h100,  32'h0, "reserved 0x100");
    expect_reg(12'hFFC,  32'h0, "reserved 0xFFC");
    item("SPI-32");
    check(cs_n === 1'b1 && sclk === 1'b0 && irq === 1'b0, "pins after reset (cs_n=1 sclk=0 irq=0)");
  endtask

  task automatic test_register_fields();
    $display("-- register fields, byte strobes, reserved offsets");
    item("SPI-02");
    apb_write(A_CTRL, 32'hFFFF_FFFE);
    check(sclk === 1'b0, "SCLK must stay at old CPOL until the next clock");
    expect_reg(A_CTRL, 32'h0000_000E, "CTRL field mask");
    check(sclk === 1'b1, "SCLK idle follows CPOL=1");
    apb_write(A_CTRL, 32'h0);
    repeat (2) @(posedge clk);
    check(sclk === 1'b0, "SCLK idle follows CPOL=0");
    item("SPI-04");
    apb_write(A_CLKDIV, 32'hFFFF_FFFF);
    expect_reg(A_CLKDIV, 32'h0000_00FF, "CLKDIV field mask");
    item("SPI-21");
    apb_write(A_CLKDIV, 32'h0000_0055, 4'b1110);
    expect_reg(A_CLKDIV, 32'h0000_00FF, "CLKDIV write with pstrb[0]=0 ignored");
    item("SPI-04");
    apb_write(A_CLKDIV + 12'h2, 32'h0000_0001);   // paddr[1:0] are don't care
    expect_reg(A_CLKDIV + 12'h3, 32'h0000_0001, "CLKDIV via unaligned address");
    item("SPI-21");
    apb_write(A_CTRL, 32'hFFFF_FF0A, 4'b0001);
    expect_reg(A_CTRL, 32'h0000_000A, "CTRL byte 0 write");
    apb_write(A_CTRL, 32'h0000_0005, 4'b0010);
    expect_reg(A_CTRL, 32'h0000_000A, "CTRL write with pstrb[0]=0 ignored");
    apb_write(A_CTRL, 32'h0);
    item("SPI-14");
    apb_write(A_IER, 32'hFFFF_FFFF);
    expect_reg(A_IER, 32'h0000_0003, "IER field mask");
    apb_write(A_IER, 32'h0);
    item("SPI-38");
    apb_write(A_ISR, 32'hFFFF_FFFF);
    expect_reg(A_ISR, 32'h0, "ISR not settable by software");
    item("SPI-08");
    apb_write(A_STATUS, 32'hFFFF_FFFF);
    expect_reg(A_STATUS, 32'h14, "STATUS is RO");
    item("SPI-12");
    apb_write(A_RXDATA, 32'hFFFF_FFFF);
    expect_reg(A_STATUS, 32'h14, "RXDATA write does nothing");
    item("SPI-16");
    apb_write(12'h020, 32'hFFFF_FFFF);
    apb_write(12'hFFC, 32'hFFFF_FFFF);
    expect_reg(A_CTRL, 32'h0, "CTRL after reserved writes");
    expect_reg(A_CLKDIV, 32'h1, "CLKDIV after reserved writes");
    expect_reg(A_CS, 32'h1, "CS after reserved writes");
    expect_reg(A_IER, 32'h0, "IER after reserved writes");
    expect_reg(12'h020, 32'h0, "reserved 0x020 after write");
  endtask

  // SPI-22: TXDATA write with PSTRB[0] = 0 pushes nothing
  // SPI-23: RXDATA read when empty returns 0, then one transfer reads back
  task automatic test_side_effects();
    logic [31:0] d;
    $display("-- side effects of TXDATA / RXDATA");
    item("SPI-22");
    apb_write(A_CTRL, 32'h0);
    apb_write(A_TXDATA, 32'h0000_00D4, 4'b1110);
    apb_read(A_STATUS, d);
    check(d[ST_TXEMPTY] === 1'b1, $sformatf("TXDATA with pstrb[0]=0 pushed a byte: STATUS %h", d));
    item("SPI-23");
    expect_reg(A_RXDATA, 32'h0, "RXDATA read while empty returns 0");
    expect_reg(A_STATUS, 32'h14, "STATUS after empty RXDATA read");
    run_bytes(1'b0, 1'b0, 1'b0, 1, '{8'h96}, '{8'h69}, 1, 1'b0);
  endtask

  task automatic test_cs_control();
    logic [31:0] d;
    $display("-- CS control");
    item("SPI-32");
    s_pat.delete(); s_idx = 0;
    apb_write(A_CS, 32'hFFFF_FFFE);
    check(cs_n === 1'b0, "CS.cs_n=0 drives pin Low");
    expect_reg(A_CS, 32'h0, "CS reads 0");
    apb_write(A_CS, 32'h0000_0001, 4'b1110);
    check(cs_n === 1'b0, "CS write with pstrb[0]=0 ignored");
    apb_write(A_CS, 32'h0000_0001);
    check(cs_n === 1'b1, "CS.cs_n=1 drives pin High");
    expect_reg(A_CS, 32'h1, "CS reads 1");
    // a transfer with CS = 1: the master still clocks, cs_n stays High
    setup_mode(1'b0, 1'b0, 1'b0, 1, 1);
    apb_write(A_TXDATA, 32'h0000_0033);
    apb_write(A_CTRL, ctrl_val(1'b1, 1'b0, 1'b0, 1'b0));
    wait_done(200, "transfer with CS = 1");
    check(cs_n === 1'b1, "cs_n stays High during a transfer with CS = 1");
    check(s_rx_q.size() == 0, "deselected slave received nothing");
    apb_read(A_RXDATA, d);
    check(d === 32'hFF, $sformatf("RXDATA %h: released MISO reads as ones", d));
    apb_write(A_CTRL, 32'h0);
    apb_write(A_ISR, 32'h3);
  endtask

  // SPI-35 busy, SPI-36 done (single byte, then burst), SPI-37 gating, SPI-38 W1C
  task automatic test_done_irq();
    logic [31:0] d;
    int          busy_seen;
    $display("-- busy, done flag (single and burst), IER gating, W1C");
    setup_mode(1'b0, 1'b1, 1'b0, 10, 1);
    s_pat = '{8'h44, 8'h11, 8'h22, 8'h33};
    apb_write(A_CS, 32'h0);
    apb_write(A_IER, 32'h1);
    item("SPI-35");
    apb_read(A_STATUS, d);
    check(d[ST_BUSY] === 1'b0, "STATUS.busy = 0 before the transfer");
    apb_write(A_TXDATA, 32'h0000_0099);
    apb_write(A_CTRL, ctrl_val(1'b1, 1'b0, 1'b1, 1'b0));
    busy_seen = 0;
    for (int k = 0; k < 4; k++) begin
      apb_read(A_STATUS, d);
      if (d[ST_BUSY] === 1'b1) busy_seen++;
    end
    check(busy_seen == 4, $sformatf("STATUS.busy = 1 while shifting (%0d of 4 polls)", busy_seen));
    item("SPI-36");
    wait_done(200, "single byte");
    check(irq === 1'b1, "irq after the single byte (done_ie = 1)");
    item("SPI-35");
    apb_read(A_STATUS, d);
    check(d[ST_BUSY] === 1'b0, "STATUS.busy = 0 after the byte");
    item("SPI-36");
    apb_write(A_ISR, 32'h1);
    check(irq === 1'b0, "irq Low after clearing done");
    expect_reg(A_RXDATA, 32'h44, "RX byte of the single transfer");
    // burst of 3: done only after the last byte
    apb_write(A_CTRL, ctrl_val(1'b0, 1'b0, 1'b1, 1'b0));
    apb_write(A_IER, 32'h0);
    apb_write(A_TXDATA, 32'h0000_00A1);
    apb_write(A_TXDATA, 32'h0000_00B2);
    apb_write(A_TXDATA, 32'h0000_00C3);
    apb_write(A_CTRL, ctrl_val(1'b1, 1'b0, 1'b1, 1'b0));
    wait_status(ST_RXEMPTY, 1'b0, 200, "first byte");
    apb_read(A_ISR, d);
    check(d[0] === 1'b0, "ISR.done must stay 0 while TX FIFO is not empty");
    item("SPI-35");
    apb_read(A_STATUS, d);
    check(d[ST_BUSY] === 1'b1, "STATUS.busy stays 1 between back-to-back bytes");
    item("SPI-36");
    wait_done(500, "3-byte burst");
    check(s_rx_q.size() == 4, $sformatf("slave got %0d bytes, expected 4", s_rx_q.size()));
    item("SPI-37");
    check(irq === 1'b0, "irq with IER=0");
    apb_write(A_IER, 32'h2);
    check(irq === 1'b0, "irq with only rx_ovr_ie (rx_ovr=0)");
    apb_write(A_IER, 32'h1);
    check(irq === 1'b1, "irq with done_ie and ISR.done");
    item("SPI-38");
    apb_write(A_ISR, 32'h1, 4'b1110);
    expect_reg(A_ISR, 32'h1, "ISR W1C with pstrb[0]=0 ignored");
    apb_write(A_ISR, 32'h0);
    expect_reg(A_ISR, 32'h1, "ISR write 0 has no effect");
    check(irq === 1'b1, "irq still High");
    apb_write(A_ISR, 32'h1);
    expect_reg(A_ISR, 32'h0, "ISR.done cleared by W1C");
    check(irq === 1'b0, "irq Low after clear");
    item("SPI-36");
    for (int k = 1; k < 4; k++) expect_reg(A_RXDATA, {24'h0, s_pat[k]}, "RX byte of the burst");
    expect_reg(A_STATUS, 32'h14, "STATUS after the burst");
    apb_write(A_IER, 32'h0);
    apb_write(A_CS, 32'h1);
    apb_write(A_CTRL, 32'h0);
  endtask

  // SPI-31: spi_en cleared during byte 2 of 4
  task automatic test_disable_mid_burst();
    logic [31:0] d;
    $display("-- clearing spi_en during a burst");
    item("SPI-31");
    setup_mode(1'b1, 1'b1, 1'b1, 5, 1);
    s_pat = '{8'h5A, 8'hC3, 8'h0F, 8'hF0};
    apb_write(A_CS, 32'h0);
    apb_write(A_TXDATA, 32'h0000_0012);
    apb_write(A_TXDATA, 32'h0000_0034);
    apb_write(A_TXDATA, 32'h0000_0056);
    apb_write(A_TXDATA, 32'h0000_0078);
    apb_write(A_CTRL, ctrl_val(1'b1, 1'b1, 1'b1, 1'b1));
    wait (s_edges_total >= 20);                      // inside byte 2
    apb_write(A_CTRL, ctrl_val(1'b0, 1'b1, 1'b1, 1'b1));
    repeat (400) @(posedge clk);
    check(s_rx_q.size() == 2, $sformatf("after spi_en=0 the current byte finishes only: %0d bytes", s_rx_q.size()));
    apb_read(A_STATUS, d);
    check(d[ST_BUSY] === 1'b0 && d[ST_TXEMPTY] === 1'b0, $sformatf("STATUS %h: idle with bytes left", d));
    expect_reg(A_ISR, 32'h0, "no done while TX FIFO not empty");
    apb_write(A_CTRL, ctrl_val(1'b1, 1'b1, 1'b1, 1'b1));
    wait_done(500, "resume");
    check(s_rx_q.size() == 4, "all 4 bytes sent after re-enable");
    if (s_rx_q.size() == 4)
      check(s_rx_q[0] == 8'h12 && s_rx_q[1] == 8'h34 && s_rx_q[2] == 8'h56 && s_rx_q[3] == 8'h78,
            "MOSI bytes after resume");
    for (int k = 0; k < 4; k++) expect_reg(A_RXDATA, {24'h0, s_pat[k]}, "RX byte after resume");
    apb_write(A_CS, 32'h1);
    apb_write(A_CTRL, 32'h0);
    apb_write(A_ISR, 32'h3);
  endtask

  // SPI-34 RX full / overrun, SPI-37 gating with both flags, SPI-38 W1C per bit
  task automatic test_rx_overflow();
    logic [31:0] d;
    $display("-- RX FIFO full and overflow");
    item("SPI-34");
    setup_mode(1'b0, 1'b0, 1'b0, 0, 1);
    s_pat.delete();
    for (int k = 0; k < 18; k++) s_pat.push_back(pat_byte(99, k));
    apb_write(A_CS, 32'h0);
    for (int k = 0; k < 16; k++) apb_write(A_TXDATA, k);
    apb_write(A_CTRL, ctrl_val(1'b1, 1'b0, 1'b0, 1'b0));
    wait_done(400, "16 bytes");
    apb_read(A_STATUS, d);
    check(d[ST_RXFULL] === 1'b1 && d[ST_RXEMPTY] === 1'b0, $sformatf("STATUS %h: RX full", d));
    expect_reg(A_ISR, 32'h1, "no rx_ovr yet");
    apb_write(A_ISR, 32'h1);
    // Pop one RX byte in the SETUP phase only: must not pop.
    @(posedge clk); #1;
    psel = 1'b1; penable = 1'b0; pwrite = 1'b0; paddr = A_RXDATA;
    repeat (3) @(posedge clk);
    #1 psel = 1'b0;
    apb_read(A_STATUS, d);
    check(d[ST_RXFULL] === 1'b1, "RXDATA in SETUP phase only must not pop");
    apb_write(A_TXDATA, 32'h0000_00EE);
    apb_write(A_TXDATA, 32'h0000_00DD);
    wait_done(400, "2 more bytes");
    expect_reg(A_ISR, 32'h3, "rx_ovr and done set");
    check(s_rx_q.size() == 18, $sformatf("slave got %0d bytes, expected 18", s_rx_q.size()));
    item("SPI-37");
    for (int ie = 0; ie < 4; ie++) begin
      apb_write(A_IER, ie);
      check(irq === (ie != 0), $sformatf("ISR=3 IER=%0d: irq=%b", ie, irq));
    end
    apb_write(A_IER, 32'h0);
    item("SPI-38");
    apb_write(A_ISR, 32'h0);
    expect_reg(A_ISR, 32'h3, "ISR write 0 changes nothing");
    apb_write(A_ISR, 32'h3, 4'b1110);
    expect_reg(A_ISR, 32'h3, "ISR write with pstrb[0]=0 changes nothing");
    apb_write(A_ISR, 32'h1);
    expect_reg(A_ISR, 32'h2, "done cleared, rx_ovr kept");
    item("SPI-37");
    apb_write(A_IER, 32'h1);
    check(irq === 1'b0, "irq: done_ie only, done=0");
    apb_write(A_IER, 32'h2);
    check(irq === 1'b1, "irq: rx_ovr_ie and rx_ovr");
    item("SPI-34");
    for (int k = 0; k < 16; k++)
      expect_reg(A_RXDATA, {24'h0, s_pat[k]}, $sformatf("RX byte %0d kept, later bytes lost", k));
    expect_reg(A_STATUS, 32'h14, "STATUS after draining RX");
    item("SPI-38");
    apb_write(A_ISR, 32'h2);
    expect_reg(A_ISR, 32'h0, "rx_ovr cleared");
    check(irq === 1'b0, "irq Low after rx_ovr clear");
    apb_write(A_IER, 32'h0);
    apb_write(A_CS, 32'h1);
    apb_write(A_CTRL, 32'h0);
  endtask

  // SPI-33 TX overflow, SPI-30 no transfer while spi_en = 0
  task automatic test_tx_full();
    logic [31:0] d;
    int edges;
    $display("-- TX FIFO full, byte dropped, no transfer while spi_en=0");
    item("SPI-33");
    setup_mode(1'b1, 1'b0, 1'b0, 1, 1);
    s_pat.delete();
    for (int k = 0; k < 17; k++) s_pat.push_back(pat_byte(7, k));
    apb_write(A_CS, 32'h0);
    for (int k = 0; k < 15; k++) apb_write(A_TXDATA, 32'h40 + k);
    apb_read(A_STATUS, d);
    check(d[ST_TXFULL] === 1'b0 && d[ST_TXEMPTY] === 1'b0 && d[ST_BUSY] === 1'b0, $sformatf("STATUS %h with 15 bytes", d));
    apb_write(A_TXDATA, 32'h4F);
    apb_read(A_STATUS, d);
    check(d[ST_TXFULL] === 1'b1, $sformatf("STATUS %h: TX full with 16 bytes", d));
    item("SPI-10");
    expect_reg(A_TXDATA, 32'h0, "TXDATA reads 0");
    item("SPI-33");
    apb_write(A_TXDATA, 32'h0000_00FF);            // dropped
    item("SPI-30");
    edges = s_edges_total;
    repeat (100) @(posedge clk);
    check(s_edges_total == edges && s_rx_q.size() == 0, "no SCLK while spi_en=0");
    apb_write(A_CTRL, ctrl_val(1'b1, 1'b1, 1'b0, 1'b0));
    item("SPI-33");
    apb_read(A_STATUS, d);
    check(d[ST_TXFULL] === 1'b0, "TX not full once the first byte is loaded");
    wait_done(1000, "16 bytes");
    check(s_rx_q.size() == 16, $sformatf("slave got %0d bytes, expected 16 (17th dropped)", s_rx_q.size()));
    for (int k = 0; k < 16 && k < s_rx_q.size(); k++)
      check(32'(s_rx_q[k]) == 32'h40 + k, $sformatf("MOSI byte %0d = %h", k, s_rx_q[k]));
    for (int k = 0; k < 16; k++) expect_reg(A_RXDATA, {24'h0, s_pat[k]}, "RX byte");
    apb_write(A_CS, 32'h1);
    apb_write(A_CTRL, 32'h0);
    apb_write(A_ISR, 32'h3);
  endtask

  // ------------------------------------------------------------------- main
  initial begin
    int seed;
    int divs[4];
    divs = '{0, 1, 3, 12};
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;
    repeat (2) @(posedge clk);

    test_reset_values();                         // pins after reset, extra reserved reads
    vp_regs();                                   // SPI-01 .. SPI-21
    test_register_fields();
    test_side_effects();                         // SPI-22, 23
    test_cs_control();                           // SPI-32

    $display("-- 4 modes, MSB / LSB first: 0xA5 0x3C out, 0x5A 0xC3 in");
    for (int m = 0; m < 4; m++)
      for (int l = 0; l < 2; l++) begin
        item((l != 0) ? "SPI-25" : "SPI-24");
        run_bytes(m[1], m[0], l[0], 1, '{8'hA5, 8'h3C}, '{8'h5A, 8'hC3}, 1, 1'b0);
      end

    $display("-- 4 modes x 2 bit orders x clk_div {0,1,3,12}, 4-byte bursts");
    seed = 1;
    for (int m = 0; m < 4; m++)
      for (int l = 0; l < 2; l++)
        for (int i = 0; i < 4; i++) begin
          item((l != 0) ? "SPI-25" : "SPI-24");
          run_burst(m[1], m[0], l[0], divs[i], 4, 1, (seed % 2) == 0, seed);
          seed++;
        end

    $display("-- one byte at clk_div 0, 1, 12, 255");
    item("SPI-26");
    run_burst(1'b0, 1'b0, 1'b0, 0,   1, 1, 1'b0, 70);
    run_burst(1'b0, 1'b1, 1'b0, 1,   1, 1, 1'b0, 71);
    run_burst(1'b1, 1'b0, 1'b0, 12,  1, 1, 1'b0, 72);
    run_burst(1'b1, 1'b1, 1'b0, 255, 1, 1, 1'b0, 73);

    $display("-- MOSI setup / hold, all modes at clk_div 0 and 3");
    item("SPI-27");
    for (int m = 0; m < 4; m++) begin
      run_burst(m[1], m[0], 1'b0, 0, 2, 1, 1'b0, 80 + m);
      run_burst(m[1], m[0], 1'b1, 3, 2, 1, 1'b0, 84 + m);
    end

    $display("-- clk_div=0 with a slave whose MISO changes 15 ns after its shift edge");
    item("SPI-28");
    for (int m = 0; m < 4; m++) run_burst(m[1], m[0], m[0] ^ m[1], 0, 3, 15, 1'b0, 50 + m);

    $display("-- back-to-back bursts of 4 and 16 bytes, clk_div=255");
    item("SPI-29");
    run_burst(1'b0, 1'b0, 1'b0, 2, 4, 1, 1'b0, 59);
    run_burst(1'b0, 1'b0, 1'b0, 0, 16, 1, 1'b0, 60);
    run_burst(1'b1, 1'b1, 1'b1, 0, 16, 1, 1'b1, 61);
    run_burst(1'b0, 1'b1, 1'b0, 255, 2, 1, 1'b0, 62);

    test_done_irq();                             // SPI-35, 36, 37, 38
    test_disable_mid_burst();                    // SPI-31
    test_rx_overflow();                          // SPI-34, 37, 38
    test_tx_full();                              // SPI-33, 30

    vplan_pkg::report(VP_BLOCK, VP_N);
    $finish;
  end

  initial begin
    #50ms;
    $display("ERROR: timeout");
    $display("TEST FAILED");
    $finish;
  end

endmodule
