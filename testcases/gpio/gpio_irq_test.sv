// gpio_irq_test: GPIO-19..23: edge interrupts
class gpio_irq_test extends gpio_base_test;
  function new();
    super.new();
    name = "gpio_irq_test";
  endfunction

  virtual task run_scenario();
    test_rise();
    test_fall_level();
    test_ie_zero();
    test_irq_or();
    test_w1c();
    test_set_wins();
  endtask

  task test_rise();
    $display("%0t: [%s] rising edge per pin", $time, name);
    item("GPIO-19");
    pins(8'h00);
    write(GPIO_IE, 32'hFF);
    for (int i = 0; i < 8; i++) begin
      pins(8'(1 << i));
      expect_reg(GPIO_IS, 32'(1 << i), $sformatf("IS after a rise on pin %0d", i));
      irq_check(1'b1, $sformatf("rise on pin %0d", i));
      pins(8'h00);
      expect_reg(GPIO_IS, 32'(1 << i), $sformatf("IS unchanged by a fall on pin %0d", i));
      write(GPIO_IS, 32'(1 << i) ^ 32'hFF, 4'b0001);    // other bits: nothing to clear
      expect_reg(GPIO_IS, 32'(1 << i), $sformatf("W1C of the other bits keeps pin %0d", i));
      write(GPIO_IS, 32'(1 << i));
      expect_reg(GPIO_IS, 32'h0, $sformatf("W1C pin %0d", i));
      irq_check(1'b0, $sformatf("after W1C of pin %0d", i));
    end
    // a pulse of one clock is caught
    drive(8'h10, 1);
    pins(8'h00);
    expect_reg(GPIO_IS, 32'h10, "a one-clock pulse sets IS");
    write(GPIO_IS, 32'hFF);
  endtask

  task test_fall_level();
    $display("%0t: [%s] falling edge and steady level", $time, name);
    item("GPIO-20");
    pins(8'hFF);
    write(GPIO_IS, 32'hFF);
    expect_reg(GPIO_IS, 32'h00, "W1C of all bits while the pins are High");
    clks(10);
    expect_reg(GPIO_IS, 32'h00, "a steady High does not set IS");
    pins(8'h00);
    expect_reg(GPIO_IS, 32'h00, "a falling edge does not set IS");
    irq_check(1'b0, "after falling edges");
  endtask

  task test_ie_zero();
    $display("%0t: [%s] GPIO_IE gates the setting of GPIO_IS", $time, name);
    item("GPIO-21");
    write(GPIO_IE, 32'h00);
    pins(8'hFF);
    expect_reg(GPIO_IS, 32'h00, "IE = 0: no IS bit set by rising edges");
    irq_check(1'b0, "IE = 0");
    pins(8'h00);
    write(GPIO_IE, 32'h0F);
    pins(8'hFF);
    expect_reg(GPIO_IS, 32'h0F, "IE = 0F: only the low nibble set");
    pins(8'h00);
    write(GPIO_IE, 32'hFF);
    expect_reg(GPIO_IS, 32'h0F, "setting IE later does not set old edges");
  endtask

  task test_irq_or();
    $display("%0t: [%s] irq_gpio_o = OR(IS & IE)", $time, name);
    item("GPIO-22");
    write(GPIO_IS, 32'hFF);
    write(GPIO_IE, 32'hFF);
    for (int i = 0; i < 8; i++) begin
      pins(8'(1 << i));
      pins(8'h00);
      irq_check(1'b1, $sformatf("only IS[%0d]", i));
      write(GPIO_IE, 32'hFF ^ 32'(1 << i));
      irq_check(1'b0, $sformatf("IE[%0d] = 0 masks it", i));
      expect_reg(GPIO_IS, 32'(1 << i), $sformatf("IS[%0d] kept while masked", i));
      write(GPIO_IE, 32'hFF);
      irq_check(1'b1, $sformatf("IE[%0d] = 1 again", i));
      write(GPIO_IS, 32'(1 << i));
      irq_check(1'b0, $sformatf("IS[%0d] cleared", i));
    end
  endtask

  task test_w1c();
    $display("%0t: [%s] W1C details", $time, name);
    item("GPIO-23");
    write(GPIO_IE, 32'hFF);
    pins(8'h0B);
    pins(8'h00);
    expect_reg(GPIO_IS, 32'h0B, "IS = 0B");
    write(GPIO_IS, 32'h00);
    expect_reg(GPIO_IS, 32'h0B, "writing 0 clears nothing");
    write(GPIO_IS, 32'hFFFF_FFFF, 4'b1110);
    expect_reg(GPIO_IS, 32'h0B, "W1C with PSTRB[0] = 0 clears nothing");
    write(GPIO_IS, 32'h0000_0003);
    expect_reg(GPIO_IS, 32'h08, "W1C of bits 1:0");
    write(GPIO_IS, 32'hFFFF_FF00);
    expect_reg(GPIO_IS, 32'h08, "W1C of reserved bits only");
    write(GPIO_IS, 32'h0000_0008);
    expect_reg(GPIO_IS, 32'h00, "W1C of bit 3");
    irq_check(1'b0, "IS = 0");
  endtask

  // A new rising edge on pin 1 and a W1C of GPIO_IS[1] at moments that move
  // one clock at a time: before, at and after the edge that sets the bit.
  // The scoreboard checks every case clock by clock; the test checks that
  // both results (cleared, kept) happened, so the window was crossed.
  task test_set_wins();
    bit [31:0] r;
    bit        saw_kept = 1'b0, saw_cleared = 1'b0;
    $display("%0t: [%s] set and W1C clear of the same bit in the same clock", $time, name);
    item("GPIO-23");
    write(GPIO_IE, 32'hFF);
    for (int b = 0; b <= 6; b++) begin
      pins(8'h02);                               // IS[1] set by an earlier edge
      pins(8'h00);
      write(GPIO_IS, 32'hFD);                    // keep only IS[1]
      wclk(1);
      fork
        drive(8'h02, 6);                         // new rising edge: IS[1] set again 3 clocks later
        begin
          wclk(b);
          write(GPIO_IS, 32'h02);
        end
      join
      clks(4);
      read(GPIO_IS, r);
      if (r[1]) saw_kept = 1'b1;
      else      saw_cleared = 1'b1;
      $display("%0t: [%s] W1C %0d clocks after the pin change: IS[1] = %b", $time, name, b, r[1]);
      write(GPIO_IS, 32'hFF);
    end
    check(saw_kept && saw_cleared, "set vs W1C: both results seen across the sweep");
    pins(8'h00);
    write(GPIO_IS, 32'hFF);
  endtask
endclass
