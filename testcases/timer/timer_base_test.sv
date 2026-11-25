// Timer base test
class timer_base_test;
  string            name = "timer_base_test";
  virtual apb_if    apb_vif;
  timer_environment env;
  apb_stimulus      stim;

  localparam bit [11:0] TCR   = 12'h000;
  localparam bit [11:0] TIER  = 12'h004;
  localparam bit [11:0] TISR  = 12'h008;
  localparam bit [11:0] TDR0  = 12'h010;
  localparam bit [11:0] TDR1  = 12'h014;
  localparam bit [11:0] TCMP0 = 12'h018;
  localparam bit [11:0] TCMP1 = 12'h01C;

  `include "apb_class_tasks.svh"
  `include "vplan/vp_timer.svh"

  function new();
  endfunction

  virtual function void build();
    env = new(apb_vif);
    env.build();
    stim = env.stim;
  endfunction

  task flush();
    env.flush();
  endtask

  virtual task run_scenario();
    vp_regs();
  endtask

  task run_test();
    $display("%0t: [%s] start", $time, name);
    build();
    env.run();
    wait (apb_vif.rst_n === 1'b1);
    run_scenario();
    flush();
    env.sb.report();
    $display("%0t: [%s] End simulation", $time, name);
    vplan_pkg::report(VP_BLOCK, VP_N, "", 1'b1);
    $finish;
  endtask

  // ---------------------------------------------------------------- helpers
  task expect_reg(input bit [11:0] addr, input bit [31:0] exp, input string what);
    rd_check(addr, exp, what);
  endtask

  task idle(input int n);
    stim.idle(n);
  endtask

  // Timer must be stopped. Load the 64-bit counter / compare value.
  task set_cnt(input bit [63:0] v);
    stim.write(TDR0, v[31:0]);
    stim.write(TDR1, v[63:32]);
  endtask

  task set_cmp(input bit [63:0] v);
    stim.write(TCMP1, v[63:32]);
    stim.write(TCMP0, v[31:0]);
  endtask

  task read_cnt(output bit [63:0] v);
    bit [31:0] lo, hi;
    stim.read(TDR0, lo);
    stim.read(TDR1, hi);
    v = {hi, lo};
  endtask

  // irq_mtip pin, read 1 ns after the last edge
  function void irq_is(input bit exp, input string what);
    check(apb_vif.irq[0] === exp, $sformatf("%s: irq_mtip = %b, expected %b", what, apb_vif.irq[0], exp));
  endfunction

  // Asynchronous reset pulse in the middle of operation
  task reset_dut();
    #2 apb_vif.rst_n = 1'b0;
    #1 irq_is(1'b0, "irq low in reset");
    stim.idle(2);
    apb_vif.rst_n = 1'b1;
  endtask
endclass
