// gpio_reg_test: GPIO-01..16: registers
class gpio_reg_test extends gpio_base_test;
  function new();
    super.new();
    name = "gpio_reg_test";
  endfunction

  virtual task run_scenario();
    vp_regs();                                   // generated register items GPIO-01..15
    item("GPIO-01");
    check_reset_values();
    test_rw_regs();
    test_outputs();
    test_reserved();
  endtask

  task test_rw_regs();
    bit [11:0] regs[3] = '{GPIO_OUT, GPIO_OE, GPIO_IE};
    string     ids[3]  = '{"GPIO-02", "GPIO-04", "GPIO-08"};
    $display("%0t: [%s] GPIO_OUT / GPIO_OE / GPIO_IE: reserved bits, strobes", $time, name);
    foreach (regs[i]) begin
      item(ids[i]);
      write(regs[i], 32'hFFFF_FFFF);
      expect_reg(regs[i], 32'h0000_00FF, $sformatf("reg %h reserved bits", regs[i]));
      write(regs[i], 32'h0000_005A);
      expect_reg(regs[i], 32'h0000_005A, $sformatf("reg %h = 5A", regs[i]));
      write(regs[i], 32'h0000_00C3, 4'b1110);
      expect_reg(regs[i], 32'h0000_005A, $sformatf("reg %h strobe 1110 ignored", regs[i]));
      write(regs[i], 32'h0000_00C3, 4'b0000);
      expect_reg(regs[i], 32'h0000_005A, $sformatf("reg %h strobe 0000 ignored", regs[i]));
      write(regs[i], 32'hFFFF_FFC3, 4'b0001);
      expect_reg(regs[i], 32'h0000_00C3, $sformatf("reg %h strobe 0001", regs[i]));
      write(regs[i], 32'h0);
    end
  endtask

  task test_outputs();
    $display("%0t: [%s] output pins follow GPIO_OUT and GPIO_OE", $time, name);
    item("GPIO-16");
    for (int v = 0; v < 256; v += 37) begin
      write(GPIO_OUT, v);
      write(GPIO_OE, {24'h0, 8'(v) ^ 8'hFF});
      #1;
      check(gpio_vif.gpio_o === 8'(v), $sformatf("gpio_o = %h, expected %h", gpio_vif.gpio_o, 8'(v)));
      check(gpio_vif.gpio_oe === (8'(v) ^ 8'hFF),
            $sformatf("gpio_oe = %h, expected %h", gpio_vif.gpio_oe, 8'(v) ^ 8'hFF));
    end
    // outputs do not loop back into GPIO_IN
    pins(8'h00);
    write(GPIO_OUT, 32'hFF);
    write(GPIO_OE,  32'hFF);
    clks(3);
    expect_reg(GPIO_IN, 32'h0, "GPIO_IN does not follow GPIO_OUT");
    write(GPIO_OUT, 32'h0);
    write(GPIO_OE,  32'h0);
  endtask

  task test_reserved();
    $display("%0t: [%s] reserved offsets", $time, name);
    item("GPIO-10");
    for (int a = 'h014; a < 'h040; a += 4) begin
      write(12'(a), 32'hFFFF_FFFF);
      expect_reg(12'(a), 32'h0, $sformatf("reserved offset %h", a));
    end
    write(12'hFFC, 32'hFFFF_FFFF);
    expect_reg(12'hFFC, 32'h0, "reserved offset FFC");
    expect_reg(GPIO_OUT, 32'h0, "GPIO_OUT after reserved writes");
    expect_reg(GPIO_IE,  32'h0, "GPIO_IE after reserved writes");
    item("GPIO-02");
    write(GPIO_OUT, 32'h3C);
    expect_reg(GPIO_OUT | 12'h1, 32'h3C, "GPIO_OUT at PADDR[1:0] = 01 (byte address bits ignored)");
    write(GPIO_OUT, 32'h0);
  endtask
endclass
