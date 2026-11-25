// timer_reg_test: TIMER-01..20: registers
class timer_reg_test extends timer_base_test;
  function new();
    super.new();
    name = "timer_reg_test";
  endfunction

  virtual task run_scenario();
    vp_regs();                                   // generated register items
    item("TIMER-15"); test_reserved();
    item("TIMER-20"); test_strobes();
  endtask

  task test_reserved();
    bit [11:0] ofs [5] = '{12'h00C, 12'h020, 12'h024, 12'h800, 12'hFFC};
    $display("%0t: [%s] reserved bits and offsets", $time, name);
    foreach (ofs[i]) begin
      write(ofs[i], 32'hFFFF_FFFF);
      expect_reg(ofs[i], 32'h0, $sformatf("reserved offset %h", ofs[i]));
    end
    expect_reg(TCR,   32'h0000_0100, "TCR after reserved writes");
    expect_reg(TCMP0, 32'hFFFF_FFFF, "TCMP0 after reserved writes");
    expect_reg(TDR0,  32'h0, "TDR0 after reserved writes");
    write(TCR, 32'hFFFF_F8FE);               // div_val = 8, timer_en = 0
    expect_reg(TCR, 32'h0000_0802, "TCR reserved bits");
    write(TIER, 32'hFFFF_FFFF);
    expect_reg(TIER, 32'h0000_0001, "TIER reserved bits");
    write(TIER, 32'h0);
    write(TISR, 32'hFFFF_FFFF);
    expect_reg(TISR, 32'h0, "TISR write ignored");
    expect_reg(TCR | 12'h3, 32'h0000_0802, "TCR at offset 0x03 (address bits 1:0 ignored)");
    write(TCR, 32'h0000_0100);
  endtask

  task test_strobes();
    bit [11:0] regs [4] = '{TDR0, TDR1, TCMP0, TCMP1};
    bit [31:0] mdl, d;
    $display("%0t: [%s] byte strobes", $time, name);
    foreach (regs[i]) begin
      write(regs[i], 32'hA5A5_5A5A);
      mdl = 32'hA5A5_5A5A;
      for (int s = 0; s < 16; s++) begin
        d = {4{8'(s * 17 + i)}} ^ 32'h0F1E_2D3C;
        write(regs[i], d, 4'(s));
        mdl = timer_model::merge(mdl, d, 4'(s));
        expect_reg(regs[i], mdl, $sformatf("reg %h strobe %b", regs[i], 4'(s)));
      end
    end
    write(TCR, 32'h0000_0100);
    write(TCR, 32'h0000_0602, 4'b0001);      // byte 0 only: div_en/timer_en
    expect_reg(TCR, 32'h0000_0102, "TCR strobe 0001");
    write(TCR, 32'h0000_0600, 4'b0010);      // byte 1 only: div_val
    expect_reg(TCR, 32'h0000_0602, "TCR strobe 0010");
    write(TCR, 32'h0000_0301, 4'b1100);
    expect_reg(TCR, 32'h0000_0602, "TCR strobe 1100");
    write(TCR, 32'h0000_0000, 4'b0000);
    expect_reg(TCR, 32'h0000_0602, "TCR strobe 0000");
    write(TIER, 32'h1, 4'b1110);
    expect_reg(TIER, 32'h0, "TIER strobe 1110");
    write(TIER, 32'h1, 4'b0001);
    expect_reg(TIER, 32'h1, "TIER strobe 0001");
    write(TIER, 32'h0);
    write(TCR, 32'h0000_0100);
    set_cnt(64'h0);
    set_cmp({64{1'b1}});
  endtask
endclass
