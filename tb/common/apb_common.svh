// Common APB master tasks and register checks for the directed testbenches.
// `include this file inside module tb_* after these declarations:
//   logic clk, psel, penable, pwrite; logic [11:0] paddr; logic [31:0] pwdata;
//   logic [3:0] pstrb; wire/logic [31:0] prdata; wire/logic pready, pslverr;
// Every check is counted against the current vplan item (vplan_pkg::item).
// Timing convention: inputs change 1 ns after a rising edge; PRDATA, PREADY
// and PSLVERR are sampled at the falling edge of the ACCESS cycle.

  logic [11:0] snap_offs[$];
  logic [31:0] snap_vals[$];

  task automatic check(input bit ok, input string what);
    vplan_pkg::chk(ok, what);
  endtask

  task automatic check_at(input string id, input bit ok, input string what);
    vplan_pkg::chk_at(id, ok, what);
  endtask

  task automatic item(input string id);
    vplan_pkg::item(id);
  endtask

  task automatic clks(input int n);
    repeat (n) @(posedge clk);
  endtask

  // ---------------------------------------------------------------- single transfers
  // A testbench that needs its own apb_write(a, d, s) / apb_read(a, d) (for
  // example to time-stamp transfers) defines TB_OWN_APB before the include.
`ifndef TB_OWN_APB
  task automatic apb_write(input logic [11:0] a, input logic [31:0] d, input logic [3:0] s = 4'hF);
    @(posedge clk); #1;
    psel = 1'b1; penable = 1'b0; pwrite = 1'b1; paddr = a; pwdata = d; pstrb = s;
    @(posedge clk); #1;
    penable = 1'b1;
    @(negedge clk);
    check(pready === 1'b1 && pslverr === 1'b0,
          $sformatf("write %h: pready=%b pslverr=%b", a, pready, pslverr));
    @(posedge clk); #1;
    psel = 1'b0; penable = 1'b0; pwrite = 1'b0; pstrb = 4'h0;
  endtask

  task automatic apb_read(input logic [11:0] a, output logic [31:0] d);
    @(posedge clk); #1;
    psel = 1'b1; penable = 1'b0; pwrite = 1'b0; paddr = a; pstrb = 4'h0;
    @(posedge clk); #1;
    penable = 1'b1;
    @(negedge clk);
    d = prdata;
    check(pready === 1'b1 && pslverr === 1'b0,
          $sformatf("read %h: pready=%b pslverr=%b", a, pready, pslverr));
    @(posedge clk); #1;
    psel = 1'b0; penable = 1'b0;
  endtask
`endif

  // SETUP phase only, then PSEL drops (no ACCESS): must have no side effect
  task automatic apb_setup_only(input logic [11:0] a, input bit write, input logic [31:0] d);
    @(posedge clk); #1;
    psel = 1'b1; penable = 1'b0; pwrite = write; paddr = a; pwdata = d; pstrb = 4'hF;
    @(posedge clk); #1;
    psel = 1'b0; pwrite = 1'b0; pstrb = 4'h0;
  endtask

  task automatic wr(input logic [11:0] a, input logic [31:0] d);
    apb_write(a, d, 4'hF);
  endtask

  task automatic rd(input logic [11:0] a, output logic [31:0] d);
    apb_read(a, d);
  endtask

  task automatic rd_check(input logic [11:0] a, input logic [31:0] exp, input string what);
    logic [31:0] d;
    apb_read(a, d);
    check(d === exp, $sformatf("%s: read %h = %h, expected %h", what, a, d, exp));
  endtask

  task automatic rd_mask(input logic [11:0] a, input logic [31:0] mask, input logic [31:0] exp,
                         input string what);
    logic [31:0] d;
    apb_read(a, d);
    check((d & mask) === (exp & mask),
          $sformatf("%s: read %h = %h, mask %h expected %h", what, a, d, mask, exp & mask));
  endtask

  // ---------------------------------------------------------------- register items
  task automatic reg_reset(input string id, input logic [11:0] a, input logic [31:0] exp);
    item(id);
    rd_check(a, exp, "reset value");
  endtask

  task automatic reg_wr_exp(input string id, input logic [11:0] a, input logic [31:0] w,
                            input logic [31:0] exp);
    item(id);
    wr(a, w);
    rd_check(a, exp, $sformatf("R/W after writing %h", w));
  endtask

  task automatic reg_ro(input string id, input logic [11:0] a);
    logic [31:0] d0, d1;
    item(id);
    rd(a, d0);
    wr(a, 32'hFFFF_FFFF);
    wr(a, 32'h0000_0000);
    rd(a, d1);
    check(d1 === d0, $sformatf("RO register %h changed by a write: %h -> %h", a, d0, d1));
  endtask

  task automatic reg_wo(input string id, input logic [11:0] a);
    item(id);
    rd_check(a, 32'h0, "write-only register reads 0");
  endtask

  task automatic res_snap();
    logic [31:0] d;
    snap_vals.delete();
    foreach (snap_offs[k]) begin
      rd(snap_offs[k], d);
      snap_vals.push_back(d);
    end
  endtask

  task automatic res_access(input string id, input logic [11:0] a);
    item(id);
    wr(a, 32'hFFFF_FFFF);
    rd_check(a, 32'h0, "reserved offset");
  endtask

  task automatic res_compare(input string id);
    logic [31:0] d;
    item(id);
    foreach (snap_offs[k]) begin
      rd(snap_offs[k], d);
      check(d === snap_vals[k], $sformatf("register %h changed after reserved writes: %h -> %h",
                                          snap_offs[k], snap_vals[k], d));
    end
  endtask

  // ---------------------------------------------------------------- APB timing items
  task automatic t_single_write(input string id, input logic [11:0] a, input logic [31:0] d0,
                                input logic [31:0] d1, input logic [31:0] d2, input logic [31:0] m);
    item(id);
    @(posedge clk); #1;
    psel = 1'b0; penable = 1'b0; pwrite = 1'b1; paddr = a; pwdata = d0; pstrb = 4'hF;
    @(posedge clk); #1;
    psel = 1'b1; pwdata = d1;                       // SETUP
    @(posedge clk); #1;
    penable = 1'b1;                                 // ACCESS
    @(negedge clk);
    check(pready === 1'b1 && pslverr === 1'b0, "single write: PREADY = 1, PSLVERR = 0 in ACCESS");
    @(posedge clk); #1;
    psel = 1'b0; penable = 1'b0; pwdata = d2;       // idle, data changes after the transfer
    @(posedge clk); #1;
    pwrite = 1'b0; pstrb = 4'h0;
    rd_mask(a, m, d1, "single write: read back D1");
  endtask

  task automatic t_cont_write(input string id, input logic [11:0] a, input logic [11:0] b,
                              input logic [31:0] d1, input logic [31:0] d2,
                              input logic [31:0] ma, input logic [31:0] mb);
    item(id);
    @(posedge clk); #1;
    psel = 1'b1; penable = 1'b0; pwrite = 1'b1; paddr = a; pwdata = d1; pstrb = 4'hF;
    @(posedge clk); #1;
    penable = 1'b1;
    @(negedge clk);
    check(pready === 1'b1 && pslverr === 1'b0, "continuous write 1: PREADY/PSLVERR");
    @(posedge clk); #1;
    penable = 1'b0; paddr = b; pwdata = d2;          // next SETUP, no idle cycle
    @(posedge clk); #1;
    penable = 1'b1;
    @(negedge clk);
    check(pready === 1'b1 && pslverr === 1'b0, "continuous write 2: PREADY/PSLVERR");
    @(posedge clk); #1;
    psel = 1'b0; penable = 1'b0; pwrite = 1'b0; pstrb = 4'h0;
    if (a == b) begin
      rd_mask(a, ma, d2, "continuous write: last value wins");
    end else begin
      rd_mask(a, ma, d1, "continuous write: first register");
      rd_mask(b, mb, d2, "continuous write: second register");
    end
  endtask

  task automatic t_single_read(input string id, input logic [11:0] a, input logic [31:0] exp,
                               input logic [31:0] m);
    item(id);
    rd_mask(a, m, exp, "single read: PRDATA in ACCESS");
  endtask

  task automatic t_cont_read(input string id, input logic [11:0] a, input logic [11:0] b,
                             input logic [31:0] ea, input logic [31:0] eb,
                             input logic [31:0] ma, input logic [31:0] mb);
    item(id);
    @(posedge clk); #1;
    psel = 1'b1; penable = 1'b0; pwrite = 1'b0; paddr = a; pstrb = 4'h0;
    @(posedge clk); #1;
    penable = 1'b1;
    @(negedge clk);
    check(pready === 1'b1 && (prdata & ma) === (ea & ma),
          $sformatf("continuous read 1: PRDATA %h expected %h", prdata & ma, ea & ma));
    @(posedge clk); #1;
    penable = 1'b0; paddr = b;                       // next SETUP, no idle cycle
    @(posedge clk); #1;
    penable = 1'b1;
    @(negedge clk);
    check(pready === 1'b1 && (prdata & mb) === (eb & mb),
          $sformatf("continuous read 2: PRDATA %h expected %h", prdata & mb, eb & mb));
    @(posedge clk); #1;
    psel = 1'b0; penable = 1'b0;
  endtask

  task automatic t_pstrb(input string id, input logic [11:0] a, input logic [31:0] m);
    logic [31:0] exp;
    item(id);
    wr(a, 32'hFFFF_FFFF);
    exp = 32'hFFFF_FFFF;
    rd_mask(a, m, exp, "PSTRB: all ones");
    for (int k = 0; k < 4; k++) begin
      apb_write(a, 32'h0, 4'(1 << k));
      exp[8*k +: 8] = 8'h00;
      rd_mask(a, m, exp, $sformatf("PSTRB = %b clears only byte %0d", 4'(1 << k), k));
    end
  endtask
