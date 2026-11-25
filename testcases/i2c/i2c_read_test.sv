// i2c_read_test: I2C-28..30: EEPROM reads
class i2c_read_test extends i2c_base_test;
  function new();
    super.new();
    name = "i2c_read_test";
  endfunction

  virtual task run_scenario();
    enable(4);
    test_ack_nack();
    test_repeated_start();
    test_rollover();
  endtask

  task test_ack_nack();
    bit nk;
    $display("%0t: [%s] read: ACK then NACK", $time, name);
    item("I2C-28");
    ee_read(12'h300, 2);
    ee_cur_read(3);                            // continues at 0x302
    ee_read(12'h010, 8);
    // dummy write (address set, STOP), then current-address read
    wr_byte(EE_W, 1'b1, 1'b0, nk);  check(!nk, "dummy write control NACKed");
    wr_byte(8'h00, 1'b0, 1'b0, nk);
    wr_byte(8'h7A, 1'b0, 1'b1, nk); check(!nk, "dummy write address NACKed");
    exp_ptr = 12'h07A;
    ee_cur_read(2);
    rd_check(STATUS, 32'h0, "after the reads: not busy, bus free, rx_nack 0");
  endtask

  task test_repeated_start();
    int unsigned s0, p0;
    $display("%0t: [%s] repeated START", $time, name);
    item("I2C-29");
    s0 = sb.n_start; p0 = sb.n_stop;
    ee_read(12'h456, 3);
    check(sb.n_start - s0 == 2 && sb.n_stop - p0 == 1,
          $sformatf("random read: %0d START and %0d STOP, expected 2 and 1", sb.n_start - s0, sb.n_stop - p0));
    // START + control(R) in one command right after a byte (repeated START)
    s0 = sb.n_start;
    ee_read(12'hFF0, 1);
    check(sb.n_start - s0 == 2, "second random read: one START, one repeated START");
  endtask

  task test_rollover();
    $display("%0t: [%s] sequential read, address rollover", $time, name);
    item("I2C-30");
    ee_read(12'hFFD, 2);
    ee_cur_read(3);                            // 0xFFF, 0x000, 0x001
    ee_read(12'hFFE, 5);                       // 0xFFE .. 0x002 in one sequential read
  endtask
endclass
