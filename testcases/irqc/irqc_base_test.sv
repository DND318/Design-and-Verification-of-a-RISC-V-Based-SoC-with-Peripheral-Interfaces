// IRQC base test
class irqc_base_test;
  string            name = "irqc_base_test";
  virtual apb_if    apb_vif;
  virtual irqc_if   irqc_vif;
  irqc_environment  env;
  apb_stimulus      stim;       // APB side (name used by apb_class_tasks.svh)
  irqc_stimulus     istim;      // interrupt-line side
  irqc_scoreboard   sb;

  // Register offsets (doc/spec/regmap.py)
  localparam bit [11:0] IRQ_PENDING = 12'h000;
  localparam bit [11:0] IRQ_ENABLE  = 12'h004;
  localparam bit [11:0] IRQ_STATUS  = 12'h008;
  localparam bit [11:0] IRQ_ID      = 12'h00C;

  `include "apb_class_tasks.svh"
  `include "vplan/vp_irqc.svh"

  function new();
  endfunction

  virtual function void build();
    env = new(apb_vif, irqc_vif);
    env.build();
    stim  = env.apb_stim;
    istim = env.stim;
    sb    = env.sb;
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
    clks(2);
    run_scenario();
    wait (istim.pkt_q.size() == 0);
    clks(4);
    flush();
    sb.report();
    $display("%0t: [%s] End simulation", $time, name);
    vplan_pkg::report(VP_BLOCK, VP_N, "", 1'b1);
    $finish;
  endtask

  // ---------------------------------------------------------------- helpers
  task wclk(input int unsigned n);
    repeat (n) @(posedge irqc_vif.clk);
    #1;
  endtask

  // {gpio, i2c, spi, uart} = v for hold clocks
  task drive(input bit [3:0] v, input int unsigned hold);
    irqc_packet p = new();
    p.data = v;
    p.hold = hold;
    istim.send(p);
  endtask

  task set_lines(input bit [3:0] v);
    drive(v, 1);
  endtask

  function void irq_is(input bit exp, input string what);
    check(apb_vif.irq[0] === exp, $sformatf("%s: irq_meip_o = %b, expected %b", what, apb_vif.irq[0], exp));
  endfunction

  task irq_check(input bit exp, input string what);
    #1;
    irq_is(exp, what);
  endtask

  task expect_reg(input bit [11:0] addr, input bit [31:0] exp, input string what);
    rd_check(addr, exp, what);
  endtask

  // ID written from the spec: lowest set bit of STATUS + 1, 0 when none
  function bit [2:0] model_id(input bit [3:0] st);
    for (int i = 0; i < 4; i++) if (st[i]) return 3'(i + 1);
    return 3'd0;
  endfunction

  task check_all(input bit [3:0] p, input bit [3:0] en, input string what);
    bit [3:0] st = p & en;
    expect_reg(IRQ_PENDING, {28'd0, p},  {what, " PENDING"});
    expect_reg(IRQ_ENABLE,  {28'd0, en}, {what, " ENABLE"});
    expect_reg(IRQ_STATUS,  {28'd0, st}, {what, " STATUS"});
    expect_reg(IRQ_ID,      {29'd0, model_id(st)}, {what, " ID"});
    irq_check(st != 4'd0, what);
  endtask
endclass
