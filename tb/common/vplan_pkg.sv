// Verification-plan bookkeeping for the directed testbenches.
// A testbench selects the current vplan item with vplan_pkg::item("UART-23"),
// every check after that is counted against that item, and report() prints
// one line per item of the block: PASS, FAIL or NOT RUN.
// "TEST PASSED" is printed only when every item ran and none failed.
package vplan_pkg;

  int unsigned n_pass[string];
  int unsigned n_fail[string];
  string       cur = "NONE";

  function automatic void item(input string id);
    cur = id;
    if (n_pass.exists(id) == 0) n_pass[id] = 0;
    if (n_fail.exists(id) == 0) n_fail[id] = 0;
  endfunction

  function automatic void chk(input bit ok, input string what);
    if (n_pass.exists(cur) == 0) item(cur);
    if (ok) begin
      n_pass[cur]++;
    end else begin
      n_fail[cur]++;
      $display("ERROR: [%0t] [%s] %s", $time, cur, what);
    end
  endfunction

  // Check counted against a fixed item, whatever the current item is
  // (for monitors and models that run in parallel with the test sequence).
  function automatic void chk_at(input string id, input bit ok, input string what);
    if (n_pass.exists(id) == 0) n_pass[id] = 0;
    if (n_fail.exists(id) == 0) n_fail[id] = 0;
    if (ok) begin
      n_pass[id]++;
    end else begin
      n_fail[id]++;
      $display("ERROR: [%0t] [%s] %s", $time, id, what);
    end
  endfunction

  function automatic int unsigned fails();
    int unsigned n = 0;
    foreach (n_fail[k]) n += n_fail[k];
    return n;
  endfunction

  // True when id is one of the space-separated IDs in list
  function automatic bit in_list(input string id, input string list);
    for (int i = 0; i + id.len() <= list.len(); i++)
      if (list.substr(i, i + id.len() - 1) == id &&
          (i + id.len() == list.len() || list.getc(i + id.len()) == " "))
        return 1'b1;
    return 1'b0;
  endfunction

  // True when id is one of <block>-01 .. <block>-<n>
  function automatic bit numbered(input string id, input string block, input int n);
    for (int i = 1; i <= n; i++)
      if (id == $sformatf("%s-%02d", block, i)) return 1'b1;
    return 1'b0;
  endfunction

  // Print the per-item table for IDs <block>-01 .. <block>-<n>.
  // ext: IDs verified outside this testbench (for example by a program run
  // with make riscv-tests); they are listed as EXT and not counted as NOT RUN.
  // partial = 1: one test of a class-based testbench, which runs only some of
  // the items; NOT RUN items do not make it fail (make vplan merges the tests).
  function automatic void report(input string block, input int n, input string ext = "",
                                 input bit partial = 1'b0);
    int n_ok = 0, n_bad = 0, n_none = 0, n_ext = 0, x_ok = 0, x_bad = 0;
    string id, st;
    $display("");
    $display("==== vplan %s: result per item ====", block);
    for (int i = 1; i <= n; i++) begin
      id = $sformatf("%s-%02d", block, i);
      if (in_list(id, ext) && (n_pass.exists(id) == 0 || (n_pass[id] + n_fail[id]) == 0)) begin
        st = "EXT";     n_ext++;
      end else if (n_pass.exists(id) == 0 || (n_pass[id] + n_fail[id]) == 0) begin
        st = "NOT RUN"; n_none++;
      end else if (n_fail[id] != 0) begin
        st = "FAIL";    n_bad++;
      end else begin
        st = "PASS";    n_ok++;
      end
      if (n_pass.exists(id) != 0)
        $display("%-9s %-7s (%0d checks, %0d failed)", id, st, n_pass[id] + n_fail[id], n_fail[id]);
      else
        $display("%-9s %-7s", id, st);
    end
    // Extra items of this block outside the numbered list (for example
    // TIMER-RND, random traffic checked by a scoreboard): shown, and a failure
    // there fails the test, but they are not part of the vplan table.
    foreach (n_pass[k]) begin
      if (k.len() > block.len() && k.substr(0, block.len()) == {block, "-"} && !numbered(k, block, n)) begin
        if (n_pass[k] + n_fail[k] == 0) continue;
        st = (n_fail[k] != 0) ? "FAIL" : "PASS";
        if (n_fail[k] != 0) x_bad++;
        else                x_ok++;
        $display("%-9s %-7s (%0d checks, %0d failed)  [extra item, not in the vplan table]",
                 k, st, n_pass[k] + n_fail[k], n_fail[k]);
      end else if (k.len() <= block.len() || k.substr(0, block.len()) != {block, "-"}) begin
        $display("warning: checks counted against unknown item %s", k);
      end
    end
    if (n_ext != 0)
      $display("==== %s: %0d items, %0d PASS, %0d FAIL, %0d NOT RUN, %0d EXT (verified by another flow) ====",
               block, n, n_ok, n_bad, n_none, n_ext);
    else
      $display("==== %s: %0d items, %0d PASS, %0d FAIL, %0d NOT RUN ====", block, n, n_ok, n_bad, n_none);
    if (x_ok + x_bad != 0)
      $display("==== %s extra items: %0d PASS, %0d FAIL ====", block, x_ok, x_bad);
    if (n_bad == 0 && x_bad == 0 && (n_none == 0 || (partial && n_ok + x_ok != 0)))
      $display("TEST PASSED");
    else
      $display("TEST FAILED");
  endfunction

endpackage
