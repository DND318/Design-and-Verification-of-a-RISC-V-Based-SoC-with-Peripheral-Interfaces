// Register-check tasks of apb_common.svh for the class-based testbenches.
// `include this file inside a test class that has an apb_stimulus handle
// named stim and a task flush(). The generated tb/unit_tests/vplan/vp_<block>.svh
// (task vp_regs) can then be included in the same class unchanged.
// Every check is counted against the current vplan item (vplan_pkg::item).
// The scoreboard also compares every read with the reference model; the
// checks here use the expected values of the register map (doc/spec/regmap.py).

  bit [11:0] snap_offs[$];
  bit [31:0] snap_vals[$];

  function void check(input bit ok, input string what);
    vplan_pkg::chk(ok, what);
  endfunction

  function void check_at(input string id, input bit ok, input string what);
    vplan_pkg::chk_at(id, ok, what);
  endfunction

  // New vplan item: let the scoreboard finish the previous one first
  task item(input string id);
    flush();
    vplan_pkg::item(id);
  endtask

  task clks(input int n);
    stim.idle(n);
  endtask

  task apb_write(input bit [11:0] a, input bit [31:0] d, input bit [3:0] s = 4'hF);
    stim.write(a, d, s);
  endtask

  task apb_read(input bit [11:0] a, output bit [31:0] d);
    stim.read(a, d);
  endtask

  task apb_setup_only(input bit [11:0] a, input bit write, input bit [31:0] d);
    stim.setup_only(a, write, d);
  endtask

  // write(addr, data) / read(addr, data): the names used by the tests of the
  // course example. wr / rd below are kept for the generated vp_<block>.svh.
  task write(input bit [11:0] a, input bit [31:0] d, input bit [3:0] s = 4'hF);
    stim.write(a, d, s);
  endtask

  task read(input bit [11:0] a, output bit [31:0] d);
    stim.read(a, d);
  endtask

  task wr(input bit [11:0] a, input bit [31:0] d);
    stim.write(a, d, 4'hF);
  endtask

  task rd(input bit [11:0] a, output bit [31:0] d);
    stim.read(a, d);
  endtask

  task rd_check(input bit [11:0] a, input bit [31:0] exp, input string what);
    bit [31:0] d;
    stim.read(a, d);
    check(d === exp, $sformatf("%s: read %h = %h, expected %h", what, a, d, exp));
  endtask

  task rd_mask(input bit [11:0] a, input bit [31:0] mask, input bit [31:0] exp, input string what);
    bit [31:0] d;
    stim.read(a, d);
    check((d & mask) === (exp & mask),
          $sformatf("%s: read %h = %h, mask %h expected %h", what, a, d, mask, exp & mask));
  endtask

  // ---------------------------------------------------------------- register items
  task reg_reset(input string id, input bit [11:0] a, input bit [31:0] exp);
    item(id);
    rd_check(a, exp, "reset value");
  endtask

  task reg_wr_exp(input string id, input bit [11:0] a, input bit [31:0] w, input bit [31:0] exp);
    item(id);
    wr(a, w);
    rd_check(a, exp, $sformatf("R/W after writing %h", w));
  endtask

  task reg_ro(input string id, input bit [11:0] a);
    bit [31:0] d0, d1;
    item(id);
    rd(a, d0);
    wr(a, 32'hFFFF_FFFF);
    wr(a, 32'h0000_0000);
    rd(a, d1);
    check(d1 === d0, $sformatf("RO register %h changed by a write: %h -> %h", a, d0, d1));
  endtask

  task reg_wo(input string id, input bit [11:0] a);
    item(id);
    rd_check(a, 32'h0, "write-only register reads 0");
  endtask

  task res_snap();
    bit [31:0] d;
    snap_vals.delete();
    foreach (snap_offs[k]) begin
      rd(snap_offs[k], d);
      snap_vals.push_back(d);
    end
  endtask

  task res_access(input string id, input bit [11:0] a);
    item(id);
    wr(a, 32'hFFFF_FFFF);
    rd_check(a, 32'h0, "reserved offset");
  endtask

  task res_compare(input string id);
    bit [31:0] d;
    item(id);
    foreach (snap_offs[k]) begin
      rd(snap_offs[k], d);
      check(d === snap_vals[k], $sformatf("register %h changed after reserved writes: %h -> %h",
                                          snap_offs[k], snap_vals[k], d));
    end
  endtask

  // ---------------------------------------------------------------- APB timing items
  // PWDATA = d0 one clock before SETUP, d1 in SETUP/ACCESS, d2 after: only d1 is written
  task t_single_write(input string id, input bit [11:0] a, input bit [31:0] d0, input bit [31:0] d1,
                      input bit [31:0] d2, input bit [31:0] m);
    item(id);
    stim.write_pre_post(a, d0, d1, d2);
    rd_mask(a, m, d1, "single write: read back D1");
  endtask

  task t_cont_write(input string id, input bit [11:0] a, input bit [11:0] b, input bit [31:0] d1,
                    input bit [31:0] d2, input bit [31:0] ma, input bit [31:0] mb);
    item(id);
    stim.write_b2b(a, d1, b, d2);
    if (a == b) begin
      rd_mask(a, ma, d2, "continuous write: last value wins");
    end else begin
      rd_mask(a, ma, d1, "continuous write: first register");
      rd_mask(b, mb, d2, "continuous write: second register");
    end
  endtask

  task t_single_read(input string id, input bit [11:0] a, input bit [31:0] exp, input bit [31:0] m);
    item(id);
    rd_mask(a, m, exp, "single read: PRDATA in ACCESS");
  endtask

  task t_cont_read(input string id, input bit [11:0] a, input bit [11:0] b, input bit [31:0] ea,
                   input bit [31:0] eb, input bit [31:0] ma, input bit [31:0] mb);
    bit [31:0] da, db;
    item(id);
    stim.read_b2b(a, b, da, db);
    check((da & ma) === (ea & ma), $sformatf("continuous read 1: PRDATA %h expected %h", da & ma, ea & ma));
    check((db & mb) === (eb & mb), $sformatf("continuous read 2: PRDATA %h expected %h", db & mb, eb & mb));
  endtask

  task t_pstrb(input string id, input bit [11:0] a, input bit [31:0] m);
    bit [31:0] exp;
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
