// gpio_input_test: GPIO-06, 17, 18: input path
class gpio_input_test extends gpio_base_test;
  function new();
    super.new();
    name = "gpio_input_test";
  endfunction

  virtual task run_scenario();
    bit [7:0]  pat[6] = '{8'h00, 8'hFF, 8'hA5, 8'h5A, 8'h01, 8'h80};
    bit [31:0] d;
    int        n;
    $display("%0t: [%s] GPIO_IN", $time, name);
    item("GPIO-17");
    foreach (pat[i]) begin
      pins(pat[i]);
      expect_reg(GPIO_IN, {24'h0, pat[i]}, $sformatf("GPIO_IN pattern %h", pat[i]));
    end
    for (int i = 0; i < 8; i++) begin
      pins(8'(1 << i));
      expect_reg(GPIO_IN, 32'(1 << i), $sformatf("GPIO_IN pin %0d alone", i));
    end
    item("GPIO-06");
    write(GPIO_IN, 32'h0000_0000);
    expect_reg(GPIO_IN, 32'h0000_0080, "GPIO_IN is read-only");

    $display("%0t: [%s] 2-FF synchronizer", $time, name);
    item("GPIO-18");
    pins(8'h00);
    // the pin changes in the SETUP cycle of a read: not visible in its ACCESS cycle
    fork
      read(GPIO_IN, d);
      drive(8'hC3, 1);
    join
    check(d === 32'h0, $sformatf("GPIO_IN = %h one clock after the pin change: not 2-FF synchronized", d));
    expect_reg(GPIO_IN, 32'hC3, "GPIO_IN two clocks later");
    // pin -> irq delay: change after edge E0, IS set at edge E0 + 3
    pins(8'h00);
    write(GPIO_IE, 32'hFF);
    fork
      drive(8'h01, 8);
      begin
        n = 0;
        wclk(1);                                 // the pin changes after this edge
        for (int k = 1; k <= 8 && n == 0; k++) begin
          wclk(1);
          if (gpio_vif.irq === 1'b1) n = k;
        end
      end
    join
    check(n == 3, $sformatf("pin-to-irq delay %0d clocks, expected 3 (2 synchronizer flops + GPIO_IS)", n));
    $display("%0t: [%s] pin-to-irq delay %0d clocks", $time, name, n);
    write(GPIO_IS, 32'hFF);
    write(GPIO_IE, 32'h00);
    pins(8'h00);
  endtask
endclass
