// GPIO base test
class gpio_base_test;
  string            name = "gpio_base_test";
  virtual apb_if    apb_vif;
  virtual gpio_if   gpio_vif;
  gpio_environment  env;
  apb_stimulus      stim;       // APB side (name used by apb_class_tasks.svh)
  gpio_stimulus     gstim;      // pin side
  gpio_scoreboard   sb;

  // Register offsets (doc/spec/regmap.py)
  localparam bit [11:0] GPIO_OUT = 12'h000;
  localparam bit [11:0] GPIO_OE  = 12'h004;
  localparam bit [11:0] GPIO_IN  = 12'h008;
  localparam bit [11:0] GPIO_IE  = 12'h00C;
  localparam bit [11:0] GPIO_IS  = 12'h010;

  `include "apb_class_tasks.svh"
  `include "vplan/vp_gpio.svh"

  function new();
  endfunction

  virtual function void build();
    env = new(apb_vif, gpio_vif);
    env.build();
    stim  = env.apb_stim;
    gstim = env.stim;
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
    wait (gstim.pkt_q.size() == 0);
    clks(4);
    flush();
    sb.report();
    $display("%0t: [%s] End simulation", $time, name);
    vplan_pkg::report(VP_BLOCK, VP_N, "", 1'b1);
    $finish;
  endtask

  // ---------------------------------------------------------------- helpers
  // Clock edges counted on the pin interface (use inside a fork instead of
  // clks(), which goes through the APB stimulus)
  task wclk(input int unsigned n);
    repeat (n) @(posedge gpio_vif.clk);
    #1;
  endtask

  // gpio_i = v for hold clocks (returns when the hold time is over)
  task drive(input bit [7:0] v, input int unsigned hold);
    gpio_packet p = new();
    p.data = v;
    p.hold = hold;
    gstim.send(p);
  endtask

  // gpio_i = v, then wait until the synchronizer and the edge detector settled
  task pins(input bit [7:0] v);
    drive(v, 4);
  endtask

  function void irq_is(input bit exp, input string what);
    check(apb_vif.irq[0] === exp, $sformatf("%s: irq_gpio_o = %b, expected %b", what, apb_vif.irq[0], exp));
  endfunction

  task irq_check(input bit exp, input string what);
    #1;
    irq_is(exp, what);
  endtask

  task expect_reg(input bit [11:0] addr, input bit [31:0] exp, input string what);
    rd_check(addr, exp, what);
  endtask

  // The register values and pins after reset
  task check_reset_values();
    expect_reg(GPIO_OUT, 32'h0, "GPIO_OUT reset");
    expect_reg(GPIO_OE,  32'h0, "GPIO_OE reset");
    expect_reg(GPIO_IN,  {24'h0, gpio_vif.gpio_i}, "GPIO_IN reset");
    expect_reg(GPIO_IE,  32'h0, "GPIO_IE reset");
    expect_reg(GPIO_IS,  32'h0, "GPIO_IS reset");
    check(gpio_vif.gpio_o === 8'h00 && gpio_vif.gpio_oe === 8'h00,
          $sformatf("pins after reset: gpio_o=%h gpio_oe=%h", gpio_vif.gpio_o, gpio_vif.gpio_oe));
    irq_check(1'b0, "after reset");
  endtask
endclass
