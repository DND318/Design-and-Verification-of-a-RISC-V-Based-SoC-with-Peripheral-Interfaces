// gpio_reset_test: reset during operation
class gpio_reset_test extends gpio_base_test;
  function new();
    super.new();
    name = "gpio_reset_test";
  endfunction

  virtual task run_scenario();
    $display("%0t: [%s] reset with the pins High", $time, name);
    item("GPIO-01");
    write(GPIO_OUT, 32'hAA);
    write(GPIO_OE,  32'h55);
    write(GPIO_IE,  32'hFF);
    pins(8'h01);
    expect_reg(GPIO_IS, 32'h01, "IS set before reset");
    drive(8'hFF, 1);
    #2 apb_vif.rst_n = 1'b0;                     // asynchronous reset, between clock edges
    #1 check(gpio_vif.gpio_o === 8'h00 && gpio_vif.gpio_oe === 8'h00 && apb_vif.irq[0] === 1'b0,
             $sformatf("outputs low in reset: gpio_o=%h gpio_oe=%h irq=%b",
                       gpio_vif.gpio_o, gpio_vif.gpio_oe, apb_vif.irq[0]));
    clks(2);
    apb_vif.rst_n = 1'b1;
    clks(4);
    check_reset_values();
    item("GPIO-21");
    write(GPIO_IE, 32'hFF);
    clks(4);
    expect_reg(GPIO_IS, 32'h00, "no edge from pins already High when IE is set");
    irq_check(1'b0, "after reset with the pins High");
    pins(8'h00);
    pins(8'h81);
    expect_reg(GPIO_IS, 32'h81, "edges work again after reset");
    write(GPIO_IS, 32'hFF);
    write(GPIO_IE, 32'h00);
  endtask
endclass
