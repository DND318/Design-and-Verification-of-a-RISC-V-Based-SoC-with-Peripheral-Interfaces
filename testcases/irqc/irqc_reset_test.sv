// irqc_reset_test: IRQC-03: reset during operation
class irqc_reset_test extends irqc_base_test;
  function new();
    super.new();
    name = "irqc_reset_test";
  endfunction

  virtual task run_scenario();
    $display("%0t: [%s] reset clears IRQ_ENABLE", $time, name);
    item("IRQC-03");
    set_lines(4'hF);
    write(IRQ_ENABLE, 32'hF);
    irq_check(1'b1, "before reset");
    #2 apb_vif.rst_n = 1'b0;                     // asynchronous reset, between clock edges
    #1 irq_is(1'b0, "in reset");
    clks(2);
    apb_vif.rst_n = 1'b1;
    clks(2);
    check_all(4'hF, 4'h0, "after reset with the lines High");
    item("IRQC-01");
    set_lines(4'h0);
    expect_reg(IRQ_PENDING, 32'h0, "IRQ_PENDING with the lines Low");
    item("IRQC-05");
    expect_reg(IRQ_STATUS, 32'h0, "IRQ_STATUS after reset");
    item("IRQC-07");
    expect_reg(IRQ_ID, 32'h0, "IRQ_ID after reset");
  endtask
endclass
