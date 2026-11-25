// I2C base test
class i2c_base_test;
  string            name = "i2c_base_test";
  virtual apb_if    apb_vif;
  virtual i2c_if    i2c_vif;
  i2c_environment   env;
  apb_stimulus      stim;       // APB side (name used by apb_class_tasks.svh)
  i2c_stimulus      istim;      // bus side
  i2c_scoreboard    sb;
  i2c_cfg           cfg;
  bit [7:0]         exp_mem[4096];
  bit [11:0]        exp_ptr;    // expected EEPROM address counter

  // Register offsets (doc/spec/regmap.py)
  localparam bit [11:0] CTRL     = 12'h000;
  localparam bit [11:0] PRESCALE = 12'h004;
  localparam bit [11:0] CMD      = 12'h008;
  localparam bit [11:0] TXDATA   = 12'h00C;
  localparam bit [11:0] RXDATA   = 12'h010;
  localparam bit [11:0] STATUS   = 12'h014;
  localparam bit [11:0] IER      = 12'h018;
  localparam bit [11:0] ISR      = 12'h01C;
  // CMD bits
  localparam bit [31:0] C_START = 32'h01;
  localparam bit [31:0] C_STOP  = 32'h02;
  localparam bit [31:0] C_WRITE = 32'h04;
  localparam bit [31:0] C_READ  = 32'h08;
  localparam bit [31:0] C_NACK  = 32'h10;
  // STATUS bits
  localparam bit [31:0] S_BUSY    = 32'h01;
  localparam bit [31:0] S_RXNACK  = 32'h02;
  localparam bit [31:0] S_BUSBUSY = 32'h04;
  // ISR / IER bits
  localparam bit [31:0] I_DONE = 32'h01;
  localparam bit [31:0] I_NACK = 32'h02;
  // EEPROM control bytes
  localparam bit [7:0]  EE_W  = 8'hA0;          // 0x50, write
  localparam bit [7:0]  EE_R  = 8'hA1;          // 0x50, read
  localparam bit [7:0]  BAD_W = 8'hA2;          // 0x51: no device

  `include "apb_class_tasks.svh"
  `include "vplan/vp_i2c.svh"

  function new();
    for (int i = 0; i < 4096; i++) exp_mem[i] = i2c_driver::pattern(i);
  endfunction

  virtual function void build();
    env = new(apb_vif, i2c_vif);
    env.build();
    stim  = env.apb_stim;
    istim = env.stim;
    sb    = env.sb;
    cfg   = env.cfg;
  endfunction

  task flush();
    env.flush();
  endtask

  virtual task run_scenario();
    vp_regs();
  endtask

  task run_test();
    $display("%0t: [%s] start", $time, name);
    build();
    env.run();
    wait (apb_vif.rst_n === 1'b1);
    clks(2);
    run_scenario();
    wait_done();
    clks(4);
    flush();
    sb.report();
    $display("%0t: [%s] %0d timing checks by the monitor, %0d EEPROM write cycles", $time, name,
             env.mon.n_tcheck, env.drv.n_write_cycles);
    $display("%0t: [%s] End simulation", $time, name);
    vplan_pkg::report(VP_BLOCK, VP_N, "", 1'b1);
    $finish;
  endtask

  // ---------------------------------------------------------------- helpers
  function void irq_is(input bit exp, input string what);
    check(apb_vif.irq[0] === exp, $sformatf("%s: irq_i2c_o = %b, expected %b", what, apb_vif.irq[0], exp));
  endfunction

  task irq_check(input bit exp, input string what);
    #1;
    irq_is(exp, what);
  endtask

  // Clock edges counted on the I2C interface (use inside a fork)
  task wclk(input int unsigned n);
    repeat (n) @(posedge i2c_vif.clk);
    #1;
  endtask

  task enable(input int unsigned presc);
    write(PRESCALE, presc);
    write(CTRL, 32'h1);
  endtask

  // Wait until the command in progress is over (scoreboard model). A command
  // takes at most START + 9 bits + STOP = 48 quarter periods; if the model
  // still waits for a bus event after 64 quarters (e.g. a STOP that never
  // came because a slave holds SDA low), the command is dropped from the
  // model and counted as a failure.
  task wait_done();
    int unsigned max_clks = 64 * (cfg.prescale + 1) + 64;
    while (max_clks > 0 && !sb.quiet()) begin
      wclk(1);
      max_clks--;
    end
    if (!sb.quiet()) begin
      check(1'b0, $sformatf("command not seen in full on the bus (model still expects %s)", sb.exp_kind[0].name()));
      sb.drop_cmd();
    end
    wclk(2);
  endtask

  // One command, then wait for its end; returns ISR (the done / nack flags
  // are cleared afterwards)
  task cmd(input bit [31:0] c, output bit [31:0] isr);
    write(CMD, c);
    wait_done();
    read(ISR, isr);
    write(ISR, I_DONE | I_NACK);
  endtask

  // Write one byte (optionally with START before / STOP after); returns NACK
  task wr_byte(input bit [7:0] b, input bit sta, input bit sto, output bit nk);
    bit [31:0] isr, st;
    write(TXDATA, b);
    cmd(C_WRITE | (sta ? C_START : 0) | (sto ? C_STOP : 0), isr);
    check(isr[0], $sformatf("write %h: ISR.done", b));
    read(STATUS, st);
    nk = st[1];
    check(isr[1] == nk, $sformatf("write %h: ISR.nack %b, STATUS.rx_nack %b", b, isr[1], nk));
  endtask

  // Read one byte, ACK or NACK it (optionally STOP after)
  task rd_byte(input bit nk, input bit sto, output bit [7:0] b);
    bit [31:0] isr, d;
    cmd(C_READ | (nk ? C_NACK : 0) | (sto ? C_STOP : 0), isr);
    check(isr == I_DONE, $sformatf("read: ISR = %h, expected done only", isr));
    read(RXDATA, d);
    b = d[7:0];
  endtask

  // Byte / page write: control, address high, address low, data, STOP, then
  // ACK polling until the write cycle is over
  task ee_write(input bit [11:0] a, input bit [7:0] d[$], input bit poll = 1'b1);
    bit nk;
    int polls;
    wr_byte(EE_W, 1'b1, 1'b0, nk);          check(!nk, "EEPROM write: control byte NACKed");
    wr_byte({4'h0, a[11:8]}, 1'b0, 1'b0, nk); check(!nk, "EEPROM write: address high NACKed");
    wr_byte(a[7:0], 1'b0, 1'b0, nk);         check(!nk, "EEPROM write: address low NACKed");
    foreach (d[i]) begin
      wr_byte(d[i], 1'b0, i == d.size() - 1, nk);
      check(!nk, $sformatf("EEPROM write: data byte %0d NACKed", i));
      exp_mem[{a[11:5], 5'(a[4:0] + i)}] = d[i];
    end
    exp_ptr = {a[11:5], 5'(a[4:0] + d.size())};   // last byte written + 1, inside the page
    if (poll) ee_poll(polls);
  endtask

  // ACK polling: START + control(W) until the device ACKs, then STOP
  task ee_poll(output int polls);
    bit nk = 1'b1;
    bit [31:0] isr;
    polls = 0;
    while (nk && polls < 50) begin
      wr_byte(EE_W, 1'b1, 1'b0, nk);
      if (nk) begin
        polls++;
        cmd(C_STOP, isr);
      end
    end
    check(!nk, "ACK polling: the device never acknowledged");
    cmd(C_STOP, isr);
  endtask

  // Read n bytes from the address counter (control(R) already sent)
  task ee_read_n(input int n, input string what);
    bit [7:0] b;
    for (int i = 0; i < n; i++) begin
      rd_byte(i == n - 1, i == n - 1, b);
      check(b === exp_mem[exp_ptr], $sformatf("%s: byte %0d at %h = %h, expected %h", what, i, exp_ptr, b, exp_mem[exp_ptr]));
      exp_ptr++;
    end
  endtask

  // Random read: dummy write of the address, repeated START, control(R), n bytes
  task ee_read(input bit [11:0] a, input int n);
    bit nk;
    wr_byte(EE_W, 1'b1, 1'b0, nk);           check(!nk, "random read: control(W) NACKed");
    wr_byte({4'h0, a[11:8]}, 1'b0, 1'b0, nk);
    wr_byte(a[7:0], 1'b0, 1'b0, nk);         check(!nk, "random read: address NACKed");
    wr_byte(EE_R, 1'b1, 1'b0, nk);           check(!nk, "random read: control(R) after repeated START NACKed");
    exp_ptr = a;
    ee_read_n(n, $sformatf("random read %h", a));
  endtask

  // Current-address read
  task ee_cur_read(input int n);
    bit nk;
    wr_byte(EE_R, 1'b1, 1'b0, nk);           check(!nk, "current read: control(R) NACKed");
    ee_read_n(n, "current-address read");
  endtask

  task slave_cfg(input bit [6:0] dev = 7'h50, input int unsigned twc = 10_000, input int unsigned taa = 5);
    i2c_packet p = new();
    p.kind = I2C_SLAVE_CFG;
    p.dev_addr = dev; p.twc_ns = twc; p.taa_ns = taa;
    istim.send(p);
  endtask

  task ext_event(input i2c_kind_e k);
    i2c_packet p = new();
    p.kind = k;
    istim.send(p);
  endtask
endclass
