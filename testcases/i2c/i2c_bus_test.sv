// i2c_bus_test: I2C-22..24, 32..34, 36: bus timing and control
class i2c_bus_test extends i2c_base_test;
  int unsigned pin_bad, pin_clks;
  bit          pin_mon;

  function new();
    super.new();
    name = "i2c_bus_test";
  endfunction

  virtual task run_scenario();
    fork
      pin_monitor();
    join_none
    test_frequency();
    test_start_stop();
    test_busy();
    test_bus_busy();
    test_disable();
    test_pins();
  endtask

  // Open-drain check on every clock (counted, checked in test_pins)
  task pin_monitor();
    pin_mon = 1;
    while (pin_mon) begin
      @(negedge i2c_vif.clk);
      if (i2c_vif.rst_n !== 1'b1) continue;
      pin_clks++;
      if (i2c_vif.scl_o !== 1'b0 || i2c_vif.sda_o !== 1'b0 ||
          (i2c_vif.scl_oe === 1'b1 && i2c_vif.scl !== 1'b0) ||
          (i2c_vif.sda_oe === 1'b1 && i2c_vif.sda !== 1'b0) ||
          (i2c_vif.scl_oe === 1'b0 && i2c_vif.ext_scl_low === 1'b0 && i2c_vif.scl !== 1'b1)) begin
        if (pin_bad < 5)
          $display("%0t: [%s] open drain: scl_o=%b sda_o=%b scl_oe=%b scl=%b sda_oe=%b sda=%b", $time, name,
                   i2c_vif.scl_o, i2c_vif.sda_o, i2c_vif.scl_oe, i2c_vif.scl, i2c_vif.sda_oe, i2c_vif.sda);
        pin_bad++;
      end
    end
  endtask

  // SCL period of the next byte: rising edge of bit 2 to rising edge of bit 3
  task measure_period(output time per);
    time t0;
    @(posedge i2c_vif.scl);
    @(posedge i2c_vif.scl);
    t0 = $time;
    @(posedge i2c_vif.scl);
    per = $time - t0;
  endtask

  task test_frequency();
    int unsigned ps[4] = '{124, 30, 4, 1};
    bit [31:0]   isr;
    time         per;
    int unsigned n0, e0;
    $display("%0t: [%s] SCL frequency", $time, name);
    item("I2C-22");
    foreach (ps[k]) begin
      enable(ps[k]);
      n0 = env.mon.n_tcheck;
      e0 = sb.n_err;
      write(TXDATA, EE_W);
      fork
        measure_period(per);
        begin
          write(CMD, C_START | C_WRITE | C_STOP);
          wait_done();
        end
      join
      check(per == 4 * (ps[k] + 1) * cfg.clk_ns,
            $sformatf("PRESCALE %0d: SCL period %0d ns, expected %0d ns (f_SCL = %0d kHz)", ps[k], per,
                      4 * (ps[k] + 1) * cfg.clk_ns, 1_000_000 / (4 * (ps[k] + 1) * cfg.clk_ns)));
      check(env.mon.n_tcheck - n0 > 20 && sb.n_err == e0,
            $sformatf("PRESCALE %0d: %0d timing checks by the monitor", ps[k], env.mon.n_tcheck - n0));
      read(ISR, isr);
      check(isr == I_DONE, "control byte with STOP: done, ACK");
      write(ISR, I_DONE);
    end
  endtask

  task test_start_stop();
    bit        nk;
    bit [31:0] isr;
    int unsigned s0, p0, e0;
    $display("%0t: [%s] START / STOP", $time, name);
    enable(4);
    item("I2C-23");
    s0 = sb.n_start; p0 = sb.n_stop; e0 = sb.n_err;
    cmd(C_START, isr);
    check(i2c_vif.scl === 1'b0 && i2c_vif.sda === 1'b0, "after START alone: SCL and SDA held low");
    cmd(C_STOP, isr);
    check(i2c_vif.scl === 1'b1 && i2c_vif.sda === 1'b1, "after STOP: bus idle");
    cmd(C_START | C_STOP, isr);                // START and STOP in one command
    cmd(C_STOP, isr);                          // STOP on an idle bus
    wr_byte(EE_W, 1'b1, 1'b0, nk);
    cmd(C_START, isr);                         // repeated START
    cmd(C_STOP, isr);
    check(sb.n_start - s0 == 4 && sb.n_stop - p0 == 4,
          $sformatf("%0d START, %0d STOP on the bus, expected 4 and 4", sb.n_start - s0, sb.n_stop - p0));
    check(sb.n_err == e0, "START / STOP setup, hold and bus free times (monitor)");
    item("I2C-24");
    e0 = sb.n_err;
    ee_read(12'h5A5, 4);
    check(sb.n_err == e0, "SDA stable while SCL high, data setup / hold (monitor)");
  endtask

  task test_busy();
    bit [31:0] isr;
    int unsigned p0;
    $display("%0t: [%s] STATUS.busy", $time, name);
    item("I2C-32");
    enable(30);
    rd_mask(STATUS, S_BUSY, 32'h0, "idle: busy = 0");
    write(TXDATA, EE_W);
    write(CMD, C_START | C_WRITE);
    rd_mask(STATUS, S_BUSY, S_BUSY, "busy right after CMD");
    clks(300);
    rd_mask(STATUS, S_BUSY, S_BUSY, "busy in the middle of the byte");
    p0 = sb.n_stop;
    write(CMD, C_STOP);                        // ignored: busy
    wait_done();
    rd_mask(STATUS, S_BUSY | S_BUSBUSY, S_BUSBUSY, "after done: busy = 0, bus still busy");
    clks(500);
    check(sb.n_stop == p0, "CMD while busy: no STOP on the bus");
    rd_check(ISR, I_DONE, "CMD while busy: only one done");
    write(ISR, I_DONE);
    cmd(C_STOP, isr);
    rd_check(STATUS, 32'h0, "STOP: bus free");
  endtask

  task test_bus_busy();
    bit [31:0] isr;
    $display("%0t: [%s] STATUS.bus_busy", $time, name);
    item("I2C-33");
    enable(4);
    cmd(C_START, isr);
    rd_check(STATUS, S_BUSBUSY, "after START: bus_busy");
    cmd(C_STOP, isr);
    rd_check(STATUS, 32'h0, "after STOP: bus_busy = 0");
    write(CTRL, 32'h0);
    ext_event(I2C_EXT_START);
    rd_check(STATUS, S_BUSBUSY, "START by another device: bus_busy");
    write(CMD, C_START | C_STOP);
    rd_mask(STATUS, S_BUSY, 32'h0, "disabled: CMD ignored");
    ext_event(I2C_EXT_STOP);
    rd_check(STATUS, 32'h0, "STOP by another device: bus_busy = 0");
  endtask

  task test_disable();
    bit [31:0] isr, d;
    bit [7:0]  w[$];
    $display("%0t: [%s] i2c_en = 0", $time, name);
    item("I2C-34");
    enable(4);
    cmd(C_START, isr);
    check(i2c_vif.scl_oe === 1'b1 && i2c_vif.sda_oe === 1'b1, "after START alone: SCL and SDA pulled low");
    write(CTRL, 32'h0);
    wclk(2);
    check(i2c_vif.scl_oe === 1'b0 && i2c_vif.sda_oe === 1'b0, "i2c_en = 0 releases both lines");
    check(i2c_vif.scl === 1'b1 && i2c_vif.sda === 1'b1, "bus idle after the release");
    clks(5);
    rd_check(STATUS, 32'h0, "release seen as STOP: bus_busy = 0");
    // abort in the middle of a byte at 100 kHz
    enable(124);
    write(TXDATA, EE_W);
    write(CMD, C_START | C_WRITE);
    wclk(1500);
    rd_check(STATUS, S_BUSY | S_BUSBUSY, "in the byte: busy and bus_busy");
    write(CTRL, 32'h0);
    wclk(2);
    check(i2c_vif.scl_oe === 1'b0 && i2c_vif.sda_oe === 1'b0, "abort: lines released");
    clks(5);
    read(STATUS, d);
    check(d[0] === 1'b0, "abort: busy = 0");
    clks(2000);
    check(i2c_vif.scl_oe === 1'b0 && i2c_vif.sda_oe === 1'b0, "abort: lines stay released");
    rd_check(ISR, 32'h0, "abort: no done");
    ext_event(I2C_EXT_STOP);                   // START + STOP by another device: bus free, slave idle
    rd_check(STATUS, 32'h0, "bus free after the abort");
    // the master works again
    enable(4);
    w = '{8'h5E, 8'hE5};
    ee_write(12'h777, w);
    ee_read(12'h777, 2);
  endtask

  task test_pins();
    $display("%0t: [%s] open-drain pins", $time, name);
    item("I2C-36");
    pin_mon = 0;
    check(pin_clks > 10000 && pin_bad == 0,
          $sformatf("open drain on %0d clocks: %0d bad (scl_o / sda_o not 0, or a line not following its enable)",
                    pin_clks, pin_bad));
  endtask
endclass
