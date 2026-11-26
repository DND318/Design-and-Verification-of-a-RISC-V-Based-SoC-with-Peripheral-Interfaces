// irqc_prio_test: IRQC-17: priority
class irqc_prio_test extends irqc_base_test;
  function new();
    super.new();
    name = "irqc_prio_test";
  endfunction

  virtual task run_scenario();
    $display("%0t: [%s] IRQ_ID priority", $time, name);
    item("IRQC-17");
    for (int e = 0; e < 16; e++) begin
      write(IRQ_ENABLE, 32'(e));
      for (int p = 0; p < 16; p++) begin
        set_lines(4'(p));
        expect_reg(IRQ_ID, {29'd0, model_id(4'(p) & 4'(e))}, $sformatf("ID pending=%b enable=%b", 4'(p), 4'(e)));
      end
    end
    // sources served one after the other: ID moves to the next one
    write(IRQ_ENABLE, 32'hF);
    set_lines(4'b1111); expect_reg(IRQ_ID, 32'd1, "all pending: UART");
    set_lines(4'b1110); expect_reg(IRQ_ID, 32'd2, "UART cleared: SPI");
    set_lines(4'b1100); expect_reg(IRQ_ID, 32'd3, "SPI cleared: I2C");
    set_lines(4'b1000); expect_reg(IRQ_ID, 32'd4, "I2C cleared: GPIO");
    set_lines(4'b0000); expect_reg(IRQ_ID, 32'd0, "none");
    // a higher-priority source masked: the next one is reported
    write(IRQ_ENABLE, 32'hE);
    set_lines(4'b0011); expect_reg(IRQ_ID, 32'd2, "UART masked: SPI");
    write(IRQ_ENABLE, 32'h0);
    set_lines(4'h0);
  endtask
endclass
