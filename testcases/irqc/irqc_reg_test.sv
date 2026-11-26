// irqc_reg_test: IRQC-01..14: registers
class irqc_reg_test extends irqc_base_test;
  function new();
    super.new();
    name = "irqc_reg_test";
  endfunction

  virtual task run_scenario();
    vp_regs();                                   // generated register items IRQC-01..14
    write(IRQ_ENABLE, 32'h0);
    $display("%0t: [%s] read-only registers with the lines High", $time, name);
    item("IRQC-02");
    set_lines(4'hF);
    write(IRQ_PENDING, 32'h0);
    expect_reg(IRQ_PENDING, 32'hF, "IRQ_PENDING is not writable");
    item("IRQC-06");
    write(IRQ_ENABLE, 32'h5);
    write(IRQ_STATUS, 32'h0);
    expect_reg(IRQ_STATUS, 32'h5, "IRQ_STATUS is not writable");
    item("IRQC-08");
    write(IRQ_ID, 32'h7);
    expect_reg(IRQ_ID, 32'h1, "IRQ_ID is not writable");
    write(IRQ_ENABLE, 32'h0);
    set_lines(4'h0);
    $display("%0t: [%s] reserved offsets", $time, name);
    item("IRQC-09");
    for (int a = 'h010; a < 'h040; a += 4) begin
      write(12'(a), 32'hFFFF_FFFF);
      expect_reg(12'(a), 32'h0, $sformatf("reserved offset %h", a));
    end
    expect_reg(IRQ_ENABLE, 32'h0, "IRQ_ENABLE after reserved writes");
    $display("%0t: [%s] byte strobes and reserved bits", $time, name);
    item("IRQC-14");
    write(IRQ_ENABLE, 32'hF);
    write(IRQ_ENABLE, 32'h0, 4'b1110);
    expect_reg(IRQ_ENABLE, 32'hF, "ENABLE strobe 1110 ignored");
    write(IRQ_ENABLE, 32'h0, 4'b0000);
    expect_reg(IRQ_ENABLE, 32'hF, "ENABLE strobe 0000 ignored");
    write(IRQ_ENABLE, 32'h5, 4'b0001);
    expect_reg(IRQ_ENABLE, 32'h5, "ENABLE strobe 0001");
    item("IRQC-04");
    write(IRQ_ENABLE, 32'hFFFF_FFF0);
    expect_reg(IRQ_ENABLE, 32'h0, "ENABLE reserved bits read 0");
    write(IRQ_ENABLE, 32'h3);
    expect_reg(IRQ_ENABLE | 12'h2, 32'h3, "ENABLE at PADDR[1:0] = 10 (byte address bits ignored)");
    write(IRQ_ENABLE, 32'h0);
  endtask
endclass
