// timer_div_test: TIMER-21..24: prescaler
class timer_div_test extends timer_base_test;
  function new();
    super.new();
    name = "timer_div_test";
  endfunction

  virtual task run_scenario();
    item("TIMER-21");
    measure_rate(32'h0000_0000, 1, "div_en=0 div_val=0");
    measure_rate(32'h0000_0800, 1, "div_en=0 div_val=8");
    item("TIMER-22");
    for (int v = 0; v <= 8; v++)
      measure_rate((v << 8) | 32'h2, 1 << v, $sformatf("div_en=1 div_val=%0d", v));
    write(TCR, 32'h0000_0100);
    measure_rate(32'h0000_0102, 2, "div_val=1 (reset) strobe 0001");
    item("TIMER-23");
    test_prohibited_div_val();
    write(TCR, 32'h0000_0402);
    write(TCR, 32'h0000_0C02);
    expect_reg(TCR, 32'h0000_0402, "TCR after prohibited 12");
    measure_rate(32'h0000_0402, 16, "div_val=4 kept after prohibited 12");
    write(TCR, 32'h0000_0100);
    item("TIMER-24");
    test_hold();
  endtask

  task measure_rate(input bit [31:0] tcr, input int unsigned period, input string what);
    bit [31:0] v0, v1, v2;
    longint unsigned c0, c1, c2;
    int unsigned m;
    write(TCR, tcr & 32'hFFFF_FFFE);         // stop, set divider
    set_cnt(64'h0);
    write(TCR, tcr | 32'h1);                 // start
    idle(3 * period + 5);
    for (int k = 0; k < 2; k++) begin
      m = (period == 1) ? 200 : (period < 16 ? 400 / period : 8);
      stim.read(TDR0, v0); c0 = stim.last_rd.cyc_sample;
      idle(m * period - 3);
      stim.read(TDR0, v1); c1 = stim.last_rd.cyc_sample;
      check(c1 - c0 == m * period, $sformatf("%s: tb window %0d", what, c1 - c0));
      check(v1 - v0 == m, $sformatf("%s: %0d ticks in %0d clocks, expected %0d (period %0d)",
                                    what, v1 - v0, c1 - c0, m, period));
      if (period > 2) begin
        idle(period - 2);
        stim.read(TDR0, v2); c2 = stim.last_rd.cyc_sample;
        check(v2 - v1 >= 1 && v2 - v1 <= 2, $sformatf("%s: %0d ticks in %0d clocks", what, v2 - v1, c2 - c1));
      end
    end
    write(TCR, tcr & 32'hFFFF_FFFE);         // stopping holds the value
    stim.read(TDR0, v0);
    idle(2 * period + 10);
    stim.read(TDR0, v1);
    check(v1 == v0, $sformatf("%s: counter moved while timer_en=0 (%0d -> %0d)", what, v0, v1));
    $display("%0t: [%s] %s: period %0d clocks OK", $time, name, what, period);
  endtask

  task test_prohibited_div_val();
    write(TCR, 32'h0000_0500);
    expect_reg(TCR, 32'h0000_0500, "TCR div_val=5");
    for (int v = 9; v < 16; v++) begin
      write(TCR, (v << 8) | 32'h2);
      expect_reg(TCR, 32'h0000_0502, $sformatf("prohibited div_val=%0d with div_en=1", v));
      write(TCR, (v << 8));
      expect_reg(TCR, 32'h0000_0500, $sformatf("prohibited div_val=%0d with div_en=0", v));
    end
    for (int v = 0; v < 9; v++) begin
      write(TCR, (v << 8));
      expect_reg(TCR, v << 8, $sformatf("legal div_val=%0d", v));
    end
    write(TCR, 32'h0000_0100);
  endtask

  task test_hold();
    bit [31:0] v0, v1;
    set_cnt(64'h0);
    write(TCR, 32'h0000_0001);
    idle(20);
    write(TCR, 32'h0000_0000);
    stim.read(TDR0, v0);
    check(v0 != 0, "counter ran while timer_en = 1");
    idle(50);
    stim.read(TDR0, v1);
    check(v1 == v0, $sformatf("counter moved while timer_en = 0: %0d -> %0d", v0, v1));
    write(TCR, 32'h0000_0100);
  endtask
endclass
