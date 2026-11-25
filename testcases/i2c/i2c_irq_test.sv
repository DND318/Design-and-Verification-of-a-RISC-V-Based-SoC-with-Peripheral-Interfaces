// i2c_irq_test: I2C-37, 38: interrupts
class i2c_irq_test extends i2c_base_test;
  function new();
    super.new();
    name = "i2c_irq_test";
  endfunction

  virtual task run_scenario();
    enable(4);
    test_gating();
    test_w1c();
    test_nack_first();
  endtask

  // ISR = v: done from a command, nack from a wrong address
  task set_isr(input bit [1:0] v);
    write(ISR, I_DONE | I_NACK);
    if (v != 2'b00) begin
      write(TXDATA, v[1] ? BAD_W : EE_W);
      write(CMD, C_START | C_WRITE | C_STOP);
      wait_done();
      if (!v[0]) write(ISR, I_DONE);
    end
    rd_check(ISR, {30'd0, v}, $sformatf("ISR set to %b", v));
  endtask

  task test_gating();
    $display("%0t: [%s] IER x ISR", $time, name);
    item("I2C-37");
    for (int s = 0; s < 4; s++) begin
      set_isr(2'(s));
      for (int e = 0; e < 4; e++) begin
        write(IER, e);
        irq_check(|(s & e), $sformatf("ISR %b, IER %b", 2'(s), 2'(e)));
      end
      write(IER, 32'h0);
    end
  endtask

  task test_w1c();
    $display("%0t: [%s] ISR W1C", $time, name);
    item("I2C-38");
    set_isr(2'b11);
    write(IER, 32'h3);
    write(ISR, 32'h3, 4'hE);
    rd_check(ISR, 32'h3, "PSTRB[0] = 0: no clear");
    write(ISR, 32'h0);
    rd_check(ISR, 32'h3, "writing 0: no clear");
    write(ISR, I_DONE);
    rd_check(ISR, I_NACK, "writing 1 to done clears only done");
    irq_check(1'b1, "nack still set: irq");
    write(ISR, I_NACK);
    rd_check(ISR, 32'h0, "writing 1 to nack clears it");
    irq_check(1'b0, "ISR = 0: irq low");
    // W1C in the middle of a command: done still comes at the end
    write(TXDATA, EE_W);
    write(CMD, C_START | C_WRITE | C_STOP);
    clks(30);
    write(ISR, I_DONE | I_NACK);
    rd_mask(STATUS, S_BUSY | S_BUSBUSY, S_BUSY | S_BUSBUSY, "W1C during the command");
    wait_done();
    rd_check(ISR, I_DONE, "done after a W1C during the command");
    irq_check(1'b1, "done with done_ie: irq");
    write(ISR, I_DONE);
    irq_check(1'b0, "done cleared: irq low");
    write(IER, 32'h0);
  endtask

  task test_nack_first();
    bit [31:0] isr;
    $display("%0t: [%s] nack before done", $time, name);
    item("I2C-37");
    write(IER, I_NACK);
    write(TXDATA, BAD_W | 8'h01);
    write(CMD, C_START | C_WRITE | C_STOP);
    @(posedge apb_vif.irq[0]);
    read(ISR, isr);
    check(isr == I_NACK, $sformatf("irq at the ACK bit: ISR = %h, expected nack only (STOP still to come)", isr));
    wait_done();
    rd_check(ISR, I_DONE | I_NACK, "after STOP: done and nack");
    rd_check(STATUS, S_RXNACK, "rx_nack, bus free");
    write(ISR, 32'h3);
    irq_check(1'b0, "irq cleared by W1C");
    write(IER, 32'h0);
  endtask
endclass
