// timer_reset_test: TIMER-30: reset during operation
class timer_reset_test extends timer_base_test;
  function new();
    super.new();
    name = "timer_reset_test";
  endfunction

  virtual task run_scenario();
    item("TIMER-30");
    set_cnt(64'h1111_2222_3333_4444);
    write(TIER, 32'h1);
    write(TCR, 32'h0000_0503);
    idle(5);
    reset_dut();
    expect_reg(TCR,   32'h0000_0100, "TCR reset");
    expect_reg(TIER,  32'h0000_0000, "TIER reset");
    expect_reg(TISR,  32'h0000_0000, "TISR reset");
    expect_reg(TDR0,  32'h0000_0000, "TDR0 reset");
    expect_reg(TDR1,  32'h0000_0000, "TDR1 reset");
    expect_reg(TCMP0, 32'hFFFF_FFFF, "TCMP0 reset");
    expect_reg(TCMP1, 32'hFFFF_FFFF, "TCMP1 reset");
    irq_is(1'b0, "irq_mtip after reset");
    idle(50);
    expect_reg(TDR0, 32'h0, "TDR0 holds while timer_en=0");
    // no irq after reset with cmp_ie = 1 and the counter running
    write(TIER, 32'h1);
    write(TCR, 32'h0000_0001);
    for (int i = 0; i < 1000; i++) begin
      idle(1);
      if (apb_vif.irq[0] !== 1'b0) begin
        check(1'b0, "irq_mtip rose after reset (TCMP must reset to all ones)");
        break;
      end
    end
    expect_reg(TISR, 32'h0, "cmp_match 0 after reset");
    write(TCR, 32'h0000_0000);
    write(TIER, 32'h0);
    set_cnt(64'h0);
    write(TCR, 32'h0000_0100);
  endtask
endclass
