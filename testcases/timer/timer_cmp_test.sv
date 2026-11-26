// timer_cmp_test: TIMER-24, 28, 29, 31, 32: compare match
class timer_cmp_test extends timer_base_test;
  function new();
    super.new();
    name = "timer_cmp_test";
  endfunction

  virtual task run_scenario();
    longint unsigned cs, ci;
    bit [63:0] v;
    item("TIMER-28");
    write(TCR, 32'h0000_0100);
    write(TIER, 32'h0);
    set_cnt(64'd0);
    set_cmp(64'd100);
    expect_reg(TISR, 32'h0, "cnt 0 < cmp 100");
    write(TDR0, 32'd99);
    expect_reg(TISR, 32'h0, "cnt 99 < cmp 100");
    write(TDR0, 32'd100);
    expect_reg(TISR, 32'h1, "cnt 100 == cmp 100");
    item("TIMER-31");
    idle(3);
    irq_is(1'b0, "irq gated by cmp_ie=0");
    write(TIER, 32'h1);
    idle(2);
    irq_is(1'b1, "irq with cmp_ie=1 and match");
    write(TIER, 32'h0);
    idle(2);
    irq_is(1'b0, "irq low after cmp_ie=0");
    expect_reg(TISR, 32'h1, "cmp_match still 1 with cmp_ie=0");
    write(TIER, 32'h1);
    item("TIMER-32");
    write(TCMP0, 32'd200);
    idle(2);
    irq_is(1'b0, "irq low after TCMP0 = 200");
    expect_reg(TISR, 32'h0, "cmp_match cleared by larger TCMP0");
    write(TDR0, 32'd201);
    expect_reg(TISR, 32'h1, "cnt 201 > cmp 200");
    idle(1);
    irq_is(1'b1, "irq at cnt 201");
    item("TIMER-29");                            // 64-bit compare: high word dominates
    set_cmp(64'h0000_0001_0000_0000);
    idle(2);
    irq_is(1'b0, "irq low after TCMP = 1_00000000");
    set_cnt(64'h0000_0000_FFFF_FFFF);
    expect_reg(TISR, 32'h0, "0_FFFFFFFF < 1_00000000");
    set_cnt(64'h0000_0001_0000_0000);
    expect_reg(TISR, 32'h1, "1_00000000 >= 1_00000000");
    set_cmp(64'h0000_0001_FFFF_FFFF);
    expect_reg(TISR, 32'h0, "1_00000000 < 1_FFFFFFFF");
    set_cnt(64'h0000_0002_0000_0000);
    expect_reg(TISR, 32'h1, "2_00000000 >= 1_FFFFFFFF");
    item("TIMER-28");                            // unsigned: bit 63 set is larger
    set_cmp(64'h7FFF_FFFF_FFFF_FFFF);
    set_cnt(64'h8000_0000_0000_0000);
    expect_reg(TISR, 32'h1, "unsigned 80.. >= 7F..");
    set_cnt(64'h7FFF_FFFF_FFFF_FFFE);
    expect_reg(TISR, 32'h0, "7F..FE < 7F..FF");
    set_cmp({64{1'b1}});
    set_cnt({64{1'b1}});
    expect_reg(TISR, 32'h1, "all-ones >= all-ones");
    set_cnt(64'h0);
    expect_reg(TISR, 32'h0, "0 < all-ones");
    idle(2);
    irq_is(1'b0, "irq low with cnt 0");
    // running timer reaches the compare value: irq one clock after the match
    item("TIMER-31");
    set_cnt(64'd1000);
    set_cmp(64'd1050);
    write(TCR, 32'h0000_0001);               // every clock
    cs = stim.last_wr.cyc_end;                   // after edge cs+k the counter is 1000+k
    ci = 0;
    for (int i = 0; i < 200 && ci == 0; i++) begin
      idle(1);
      if (apb_vif.irq[0] === 1'b1) ci = apb_vif.cyc;
    end
    check(ci != 0, "irq never rose while counting to TCMP");
    check(ci == cs + 51, $sformatf("irq rose after edge %0d, expected %0d (1 clock latency)", ci - cs, 51));
    expect_reg(TISR, 32'h1, "cmp_match while running past TCMP");
    item("TIMER-32");                            // clear while running: larger TCMP1
    write(TCMP1, 32'h0000_0001);
    idle(2);
    irq_is(1'b0, "irq low after TCMP1 = 1 while running");
    expect_reg(TISR, 32'h0, "cmp_match 0 after larger TCMP1");
    write(TCR, 32'h0000_0000);
    item("TIMER-24");                            // disabling does not clear the counter
    read_cnt(v);
    check(v > 64'd1050 && v < 64'd2000, $sformatf("counter kept after timer_en=0: %h", v));
    write(TIER, 32'h0);
    set_cmp({64{1'b1}});
    write(TCR, 32'h0000_0100);
  endtask
endclass
