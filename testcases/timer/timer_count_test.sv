// timer_count_test: TIMER-25..27: 64-bit counter
class timer_count_test extends timer_base_test;
  function new();
    super.new();
    name = "timer_count_test";
  endfunction

  virtual task run_scenario();
    test_carry();                                // TIMER-25, 26
    item("TIMER-27");
    test_write_wins();
  endtask

  // Exact count over a known number of enabled clocks (div_en = 0): timer_en
  // is 1 from the edge after the start write up to the stop-write edge.
  task run_clocks(input int n, output longint unsigned ticks);
    longint unsigned cs;
    write(TCR, 32'h0000_0001);
    cs = stim.last_wr.cyc_end;
    idle(n);
    write(TCR, 32'h0000_0000);
    ticks = stim.last_wr.cyc_end - cs;
  endtask

  task test_carry();
    bit [63:0] v, start;
    longint unsigned t;
    item("TIMER-25");
    start = 64'h1234_5678_FFFF_FFF0;
    set_cnt(start);
    run_clocks(30, t);
    read_cnt(v);
    check(v == start + t, $sformatf("carry TDR0->TDR1: %h expected %h", v, start + t));
    check(v[63:32] == 32'h1234_5679, $sformatf("TDR1 after carry = %h", v[63:32]));
    item("TIMER-26");
    start = 64'hFFFF_FFFF_FFFF_FFF8;
    set_cnt(start);
    run_clocks(20, t);
    read_cnt(v);
    check(v == start + t, $sformatf("64-bit wrap: %h expected %h", v, start + t));
    check(v[63:32] == 32'h0, "64-bit wrap TDR1 = 0");
    item("TIMER-25");                            // carry with the prescaler (P = 4)
    set_cnt(64'h0000_0000_FFFF_FFFE);
    write(TCR, 32'h0000_0203);
    idle(40);
    write(TCR, 32'h0000_0202);
    read_cnt(v);
    check(v >= 64'h1_0000_0008 && v <= 64'h1_0000_000C, $sformatf("carry with prescaler: %h", v));
    write(TCR, 32'h0000_0100);
  endtask

  task test_write_wins();
    bit [31:0] d, lo, hi, e;
    bit [63:0] v;
    longint unsigned cw, cs, c0;
    set_cnt(64'h0);
    write(TCR, 32'h0000_0001);               // count every clock
    idle(10);
    write(TDR0, 32'h0000_1000);              // no increment at the write edge
    cw = stim.last_wr.cyc_end;
    stim.read(TDR0, d);
    cs = stim.last_rd.cyc_sample;
    e = 32'h1000 + 32'(cs - cw);
    check(d == e, $sformatf("TDR0 write while running: %h expected %h", d, e));
    // byte-strobe write while running: written byte replaced, others hold
    write(TCR, 32'h0000_0000);
    set_cnt(64'h0000_0007_1234_5610);
    write(TCR, 32'h0000_0001);
    c0 = stim.last_wr.cyc_end;
    write(TDR0, 32'h00AB_0000, 4'b0100);
    cw = stim.last_wr.cyc_end;
    stim.read(TDR0, d);
    cs = stim.last_rd.cyc_sample;
    e = timer_model::merge(32'h1234_5610 + 32'(cw - 1 - c0), 32'h00AB_0000, 4'b0100) + 32'(cs - cw);
    check(d == e, $sformatf("TDR0 byte-2 write while running: %h expected %h", d, e));
    // TDR1 write while running: whole counter held in that clock
    write(TCR, 32'h0000_0000);
    set_cnt(64'h0);
    write(TCR, 32'h0000_0001);
    cs = stim.last_wr.cyc_end;
    idle(5);
    write(TDR1, 32'h0000_0055);
    write(TCR, 32'h0000_0000);
    read_cnt(v);
    {hi, lo} = v;
    check(hi == 32'h55, $sformatf("TDR1 written while running: %h", hi));
    check(lo == 32'((stim.last_wr.cyc_end - cs) - 1),
          $sformatf("TDR0 during TDR1 write: %0d expected %0d", lo, (stim.last_wr.cyc_end - cs) - 1));
    write(TCR, 32'h0000_0100);
  endtask
endclass
