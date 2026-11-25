// i2c_write_test: I2C-25..27, 31: EEPROM writes
class i2c_write_test extends i2c_base_test;
  function new();
    super.new();
    name = "i2c_write_test";
  endfunction

  virtual task run_scenario();
    enable(4);
    test_address();
    test_byte_write();
    test_page_write();
    test_ack_polling();
  endtask

  task test_address();
    bit        nk;
    bit [31:0] isr;
    $display("%0t: [%s] address ACK / NACK", $time, name);
    item("I2C-25");
    wr_byte(EE_W, 1'b1, 1'b1, nk);
    check(!nk, "control byte 0x50 acknowledged");
    rd_check(STATUS, 32'h0, "after STOP: rx_nack 0, bus free, not busy");
    item("I2C-26");
    write(TXDATA, BAD_W);
    write(CMD, C_START | C_WRITE);
    wait_done();
    rd_check(ISR, I_DONE | I_NACK, "wrong address: done and nack");
    rd_check(STATUS, S_RXNACK | S_BUSBUSY, "wrong address: rx_nack, bus still busy (no STOP)");
    cmd(C_STOP, isr);
    rd_check(STATUS, S_RXNACK, "after STOP: rx_nack kept, bus free");
    check(env.drv.n_ctrl_nacked == 1, "slave saw one control byte for another address");
    write(TXDATA, BAD_W | 8'h01);              // read from a missing device, with STOP
    write(CMD, C_START | C_WRITE | C_STOP);
    wait_done();
    rd_check(ISR, I_DONE | I_NACK, "wrong address read: done and nack");
    item("I2C-25");
    write(ISR, I_DONE | I_NACK);
    wr_byte(EE_W, 1'b1, 1'b1, nk);
    check(!nk, "good address after a NACK");
    rd_check(STATUS, 32'h0, "rx_nack cleared by the next ACK");
  endtask

  task test_byte_write();
    bit [7:0] d[$];
    $display("%0t: [%s] byte write", $time, name);
    item("I2C-27");
    d = '{8'h3C};
    ee_write(12'h123, d);
    ee_read(12'h123, 1);
    ee_read(12'h120, 6);                       // around the written byte
  endtask

  task test_page_write();
    bit [7:0] d[$];
    $display("%0t: [%s] page write, page wrap", $time, name);
    item("I2C-27");
    d = '{8'hC0, 8'hC1, 8'hC2, 8'hC3};
    ee_write(12'h05E, d);                      // 0x5E, 0x5F, wrap to 0x40, 0x41
    check(exp_mem[12'h040] === 8'hC2 && exp_mem[12'h041] === 8'hC3, "page wrap in the expected memory");
    ee_read(12'h05C, 6);                       // 0x5C..0x61: 0x60 / 0x61 not written
    ee_read(12'h03F, 4);                       // 0x3F..0x42
    d.delete();
    for (int i = 0; i < 32; i++) d.push_back(8'(i * 5 + 1));
    ee_write(12'h200, d);                      // a full page
    ee_read(12'h1FF, 34);
  endtask

  task test_ack_polling();
    bit [7:0] d[$];
    int       polls;
    bit       nk;
    $display("%0t: [%s] ACK polling", $time, name);
    item("I2C-31");
    d = '{8'h99, 8'h66};
    ee_write(12'hABC, d, 1'b0);                // no polling inside
    ee_poll(polls);
    check(polls >= 1, $sformatf("ACK polling: %0d NACKs during the write cycle, expected >= 1", polls));
    $display("%0t: [%s] ACK polling: %0d NACKs", $time, name, polls);
    // a longer write cycle: more polls
    slave_cfg(7'h50, 40_000);
    d = '{8'h11};
    ee_write(12'hABE, d, 1'b0);
    ee_poll(polls);
    check(polls >= 5, $sformatf("ACK polling with tWC = 40 us: %0d NACKs, expected >= 5", polls));
    slave_cfg();
    ee_read(12'hABC, 3);
  endtask
endclass
