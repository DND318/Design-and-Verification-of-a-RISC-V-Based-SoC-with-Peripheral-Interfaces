// irqc_func_test: IRQC-15, 16, 18, 19: pending / enable / irq output
class irqc_func_test extends irqc_base_test;
  function new();
    super.new();
    name = "irqc_func_test";
  endfunction

  virtual task run_scenario();
    test_raw_lines();
    test_all_combinations();
    test_no_state();
    test_enable_after_pending();
  endtask

  task test_raw_lines();
    $display("%0t: [%s] raw lines", $time, name);
    item("IRQC-15");
    for (int i = 0; i < 4; i++) begin
      set_lines(4'(1 << i));
      expect_reg(IRQ_PENDING, 32'(1 << i), $sformatf("line %0d alone", i));
    end
    set_lines(4'hF); expect_reg(IRQ_PENDING, 32'hF, "all lines");
    set_lines(4'h0); expect_reg(IRQ_PENDING, 32'h0, "no line");
  endtask

  task test_all_combinations();
    $display("%0t: [%s] all 16 x 16 PENDING x ENABLE combinations", $time, name);
    item("IRQC-16");
    for (int e = 0; e < 16; e++) begin
      write(IRQ_ENABLE, 32'(e));
      for (int p = 0; p < 16; p++) begin
        set_lines(4'(p));
        check_all(4'(p), 4'(e), $sformatf("pending=%b enable=%b", 4'(p), 4'(e)));
      end
    end
    set_lines(4'h0);
  endtask

  task test_no_state();
    $display("%0t: [%s] no state: irq_meip_o follows the lines", $time, name);
    item("IRQC-18");
    write(IRQ_ENABLE, 32'hF);
    for (int i = 0; i < 4; i++) begin
      set_lines(4'(1 << i));
      irq_check(1'b1, $sformatf("line %0d High", i));
      set_lines(4'h0);
      irq_check(1'b0, $sformatf("line %0d dropped", i));
      check_all(4'h0, 4'hF, $sformatf("nothing kept after line %0d", i));
    end
    // a line High for one clock only
    drive(4'h4, 1);
    irq_check(1'b1, "one-clock pulse on line 2");
    set_lines(4'h0);
    irq_check(1'b0, "after the one-clock pulse");
    expect_reg(IRQ_PENDING, 32'h0, "the pulse is not latched");
  endtask

  task test_enable_after_pending();
    $display("%0t: [%s] enable a line that is already pending", $time, name);
    item("IRQC-19");
    write(IRQ_ENABLE, 32'h0);
    for (int i = 0; i < 4; i++) begin
      set_lines(4'(1 << i));
      irq_check(1'b0, $sformatf("line %0d pending, ENABLE = 0", i));
      write(IRQ_ENABLE, 32'(1 << i));
      irq_check(1'b1, $sformatf("right after enabling line %0d", i));
      expect_reg(IRQ_STATUS, 32'(1 << i), $sformatf("STATUS after enabling line %0d", i));
      write(IRQ_ENABLE, 32'h0);
      irq_check(1'b0, $sformatf("after disabling line %0d", i));
      set_lines(4'h0);
    end
  endtask
endclass
