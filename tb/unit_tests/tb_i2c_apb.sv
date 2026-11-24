`timescale 1ns/1ps
// Directed, self-checking testbench for i2c_apb (I2C master, APB slot 2).
// The bus is wired-AND with pull-ups: a line is 0 when the master (oe = 1),
// the EEPROM model or the testbench pulls it low, else 1.
// START/STOP are legal only on the SCL high phase that follows a complete byte
// (9 clocks) or a START, i.e. when the SCL rising edges since the START are 1 mod 9.
// Checks against an independent 24LC32A EEPROM model (tb/models/i2c_eeprom_24lc32a.sv)
// and a bus protocol checker: SDA may change while SCL is high only as START/STOP at a
// byte boundary, master SDA changes respect setup/hold of one quarter period,
// START hold, STOP setup and bus-free times, and SCL period / high time are measured.
// Checks are grouped by vplan item (doc/vplan, sheet I2C); the protocol checker
// counts against fixed items (I2C-23 START/STOP timing, I2C-24 SDA stable,
// I2C-36 pins). The log ends with a PASS / FAIL / NOT RUN line per item, then
// "TEST PASSED" or "TEST FAILED" for scripts/check_log.sh.
module tb_i2c_apb;

  localparam int CLK_NS = 20;  // 50 MHz

  localparam logic [11:0] A_CTRL  = 12'h000;
  localparam logic [11:0] A_PRESC = 12'h004;
  localparam logic [11:0] A_CMD   = 12'h008;
  localparam logic [11:0] A_TX    = 12'h00C;
  localparam logic [11:0] A_RX    = 12'h010;
  localparam logic [11:0] A_STAT  = 12'h014;
  localparam logic [11:0] A_IER   = 12'h018;
  localparam logic [11:0] A_ISR   = 12'h01C;

  localparam logic [7:0] C_START = 8'h01;
  localparam logic [7:0] C_STOP  = 8'h02;
  localparam logic [7:0] C_WRITE = 8'h04;
  localparam logic [7:0] C_READ  = 8'h08;
  localparam logic [7:0] C_NACK  = 8'h10;

  localparam logic [7:0] EE_W  = 8'hA0;   // 0x50 << 1 | 0
  localparam logic [7:0] EE_R  = 8'hA1;   // 0x50 << 1 | 1
  localparam logic [7:0] BAD_W = 8'hA2;   // 0x51: no device

  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic        psel = 1'b0, penable = 1'b0, pwrite = 1'b0;
  logic [11:0] paddr = 12'h0;
  logic [31:0] pwdata = 32'h0;
  logic [3:0]  pstrb = 4'h0;
  wire  [31:0] prdata;
  wire         pready, pslverr;
  wire         scl_o, scl_oe, sda_o, sda_oe, irq;
  wire         ee_sda_low;
  logic        tb_scl_low = 1'b0, tb_sda_low = 1'b0;   // a second "device" on the bus

  // Wired-AND bus with pull-ups.
  wire scl_bus = (scl_oe || tb_scl_low) ? 1'b0 : 1'b1;
  wire sda_bus = (sda_oe || ee_sda_low || tb_sda_low) ? 1'b0 : 1'b1;


  always #(CLK_NS/2) clk = ~clk;

  i2c_apb dut (
    .clk_i(clk), .rst_ni(rst_n),
    .psel_i(psel), .penable_i(penable), .pwrite_i(pwrite), .paddr_i(paddr),
    .pwdata_i(pwdata), .pstrb_i(pstrb), .prdata_o(prdata), .pready_o(pready), .pslverr_o(pslverr),
    .i2c_scl_o(scl_o), .i2c_scl_oe_o(scl_oe), .i2c_scl_i(scl_bus),
    .i2c_sda_o(sda_o), .i2c_sda_oe_o(sda_oe), .i2c_sda_i(sda_bus),
    .irq_i2c_o(irq)
  );

  i2c_eeprom_24lc32a #(.DEV_ADDR(7'h50)) u_ee (
    .scl_i(scl_bus), .sda_i(sda_bus), .sda_drive_low_o(ee_sda_low)
  );

`include "apb_common.svh"
`include "vplan/vp_i2c.svh"

  // ------------------------------------------------------------------ protocol checker
  bit  chk_en = 1'b0;
  time q_ns = 125 * CLK_NS;         // expected quarter period for the current prescale
  int  n_start = 0, n_stop = 0;
  int  bitpos = 0;                   // SCL rising edges since the last START
  bit  in_xfer = 1'b0;
  time t_scl_rise = 0, t_scl_fall = 0, t_start = 0, t_stop = 0, t_msda = 0;
  bit  msda_pending = 1'b0;          // master changed SDA since the last SCL rise
  bit  start_hold_pending = 1'b0;
  logic ack_sda = 1'b1;              // SDA at the 9th SCL rise of the last byte
  int  per_min, per_max, hi_min, hi_max, n_meas;

  task automatic meas_reset();
    per_min = 32'h7fffffff; per_max = 0; hi_min = 32'h7fffffff; hi_max = 0; n_meas = 0;
  endtask

  always @(negedge sda_bus) begin
    if (scl_bus === 1'b1) begin                      // START
      if (chk_en && in_xfer)
        check_at("I2C-24", (bitpos % 9) == 1,
                 $sformatf("protocol: SDA fell while SCL high inside a byte (bit %0d)", bitpos % 9));
      if (chk_en && n_stop > 0 && !in_xfer)
        check_at("I2C-23", ($time - t_stop) >= q_ns,
                 $sformatf("protocol: bus free time %0t < quarter", $time - t_stop));
      if (chk_en && in_xfer)
        check_at("I2C-23", ($time - t_scl_rise) >= q_ns, "protocol: repeated START setup time below one quarter");
      n_start++;
      in_xfer = 1'b1;
      bitpos = 0;
      t_start = $time;
      start_hold_pending = 1'b1;
    end
  end

  always @(posedge sda_bus) begin
    if (scl_bus === 1'b1) begin                      // STOP
      if (chk_en && in_xfer)
        check_at("I2C-24", (bitpos % 9) == 1,
                 $sformatf("protocol: SDA rose while SCL high inside a byte (bit %0d)", bitpos % 9));
      if (chk_en)
        check_at("I2C-23", ($time - t_scl_rise) >= q_ns, "protocol: STOP setup time below one quarter");
      n_stop++;
      in_xfer = 1'b0;
      t_stop = $time;
    end
  end

  always @(posedge scl_bus) begin
    if (chk_en && msda_pending)
      check_at("I2C-24", ($time - t_msda) >= q_ns,
               $sformatf("protocol: SDA setup %0t before SCL rise < quarter", $time - t_msda));
    msda_pending = 1'b0;
    if (in_xfer) begin
      bitpos++;
      if ((bitpos % 9) == 0) ack_sda = sda_bus;     // 9th clock: ACK / NACK bit
      if ((bitpos % 9) != 1) begin                   // consecutive clocks inside one byte
        int per;
        per = int'($time - t_scl_rise);
        if (per < per_min) per_min = per;
        if (per > per_max) per_max = per;
        n_meas++;
      end
    end
    t_scl_rise = $time;
  end

  always @(negedge scl_bus) begin
    if (in_xfer && bitpos > 0) begin
      int hi;
      hi = int'($time - t_scl_rise);
      if (hi < hi_min) hi_min = hi;
      if (hi > hi_max) hi_max = hi;
    end
    if (chk_en && start_hold_pending)
      check_at("I2C-23", ($time - t_start) >= q_ns, "protocol: START hold time below one quarter");
    start_hold_pending = 1'b0;
    t_scl_fall = $time;
  end

  // Master-driven SDA changes: only while SCL is low, at least a quarter after SCL fell.
  always @(sda_oe) begin
    if (scl_bus === 1'b0) begin
      if (chk_en)
        check_at("I2C-24", ($time - t_scl_fall) >= q_ns,
                 $sformatf("protocol: SDA hold %0t after SCL fall < quarter", $time - t_scl_fall));
      t_msda = $time;
      msda_pending = 1'b1;
    end
  end

  // Pins: *_o tied to 0 (open drain), APB response constant. Counted once per
  // change of the line enables, failures reported at once.
  int pin_bad = 0;
  always @(posedge clk) begin
    if (rst_n && (scl_o !== 1'b0 || sda_o !== 1'b0 || pready !== 1'b1 || pslverr !== 1'b0)) begin
      pin_bad++;
      if (pin_bad <= 5)
        check_at("I2C-36", 1'b0, $sformatf("scl_o=%b sda_o=%b must be 0, pready %b pslverr %b",
                                           scl_o, sda_o, pready, pslverr));
    end
  end
  always @(scl_oe or sda_oe)
    if (rst_n) check_at("I2C-36", scl_o === 1'b0 && sda_o === 1'b0, "scl_o / sda_o not 0 while oe changes");

  // ------------------------------------------------------------------ APB helpers
  task automatic expect_reg(input logic [11:0] a, input logic [31:0] exp, input string what);
    logic [31:0] d;
    apb_read(a, d);
    check(d === exp, $sformatf("%s: read 0x%08h expected 0x%08h", what, d, exp));
  endtask

  task automatic set_prescale(input int p);
    int q;
    q = (p + 1) * CLK_NS;
    apb_write(A_PRESC, 32'(p), 4'h3);
    q_ns = time'(q);
  endtask

  // ------------------------------------------------------------------ I2C helpers
  // Wait for ISR.done, return ISR, then clear both flags.
  task automatic wait_done(output logic [31:0] isr);
    int n = 0;
    isr = 32'h0;
    while (!isr[0] && n < 200000) begin
      apb_read(A_ISR, isr);
      n++;
    end
    check(isr[0] === 1'b1, "timeout waiting for ISR.done");
  endtask

  task automatic i2c_cmd(input logic [7:0] cmd, output logic [31:0] isr);
    logic [31:0] st;
    apb_write(A_CMD, {24'h0, cmd}, 4'h1);
    apb_read(A_STAT, st);
    check_at("I2C-32", st[0] === 1'b1, $sformatf("STATUS.busy not set after CMD 0x%02h", cmd));
    wait_done(isr);
    apb_read(A_STAT, st);
    check_at("I2C-32", st[0] === 1'b0, "STATUS.busy still set after ISR.done");
    apb_write(A_ISR, 32'h3, 4'h1);
  endtask

  // Write one byte, return the slave ACK bit (1 = NACK); checks STATUS.rx_nack == ISR.nack.
  task automatic i2c_wr(input logic [7:0] b, input bit sta, input bit sto, output bit nack);
    logic [31:0] isr, st;
    apb_write(A_TX, {24'h0, b}, 4'h1);
    i2c_cmd(C_WRITE | (sta ? C_START : 8'h0) | (sto ? C_STOP : 8'h0), isr);
    apb_read(A_STAT, st);
    nack = st[1];
    check(isr[1] === st[1], $sformatf("ISR.nack=%b but STATUS.rx_nack=%b", isr[1], st[1]));
  endtask

  task automatic i2c_rd(input bit nack, input bit sto, output logic [7:0] b);
    logic [31:0] isr, d;
    i2c_cmd(C_READ | (nack ? C_NACK : 8'h0) | (sto ? C_STOP : 8'h0), isr);
    check(isr[1] === 1'b0, "ISR.nack set by a read command");
    apb_read(A_RX, d);
    b = d[7:0];
  endtask

  // ------------------------------------------------------------------ EEPROM helpers
  logic [7:0]  exp_mem [0:4095];
  logic [11:0] exp_ptr = 12'h000;
  logic [7:0]  wbuf [0:63];
  logic [7:0]  rbuf [0:63];

  function automatic logic [7:0] pattern(input int a);   // initial content, from the model header
    return 8'((a * 37 + (a >> 8) * 11 + 5) & 255);
  endfunction

  // ACK polling: START + control(W) + STOP until the device acknowledges.
  task automatic ee_ack_poll(output int polls);
    bit nk = 1'b1;
    polls = 0;
    while (nk && polls < 200) begin
      i2c_wr(EE_W, 1'b1, 1'b1, nk);
      if (nk) polls++;
    end
    check_at("I2C-31", !nk, "ACK polling: device never acknowledged");
  endtask

  task automatic ee_write(input logic [11:0] addr, input int n, input bit poll);
    bit nk;
    int polls, s0, p0;
    logic [11:0] a;
    s0 = n_start; p0 = n_stop;
    i2c_wr(EE_W, 1'b1, 1'b0, nk);           check_at("I2C-25", !nk, "write: control byte NACKed");
    check_at("I2C-25", bitpos == 9, $sformatf("address byte: %0d SCL pulses, expected 9", bitpos));
    i2c_wr({4'h0, addr[11:8]}, 1'b0, 1'b0, nk); check(!nk, "write: address high NACKed");
    i2c_wr(addr[7:0], 1'b0, 1'b0, nk);       check(!nk, "write: address low NACKed");
    a = addr;
    for (int i = 0; i < n; i++) begin
      i2c_wr(wbuf[i], 1'b0, (i == n - 1), nk);
      check(!nk, $sformatf("write: data byte %0d NACKed", i));
      exp_mem[a] = wbuf[i];
      a = {a[11:5], a[4:0] + 5'd1};           // page wrap
    end
    exp_ptr = a;
    check(n_start - s0 == 1 && n_stop - p0 == 1,
          $sformatf("write: saw %0d START / %0d STOP, expected 1/1", n_start - s0, n_stop - p0));
    if (poll) begin
      ee_ack_poll(polls);
      $display("[%0t] INFO: write of %0d byte(s) at 0x%03h, ACK polling NACKed %0d time(s)",
               $time, n, addr, polls);
      check_at("I2C-31", polls >= 1, "ACK polling: expected at least one NACK during the write cycle");
    end
  endtask

  task automatic ee_read_bytes(input int n);
    for (int i = 0; i < n; i++) begin
      logic [7:0] b;
      i2c_rd((i == n - 1), (i == n - 1), b);
      rbuf[i] = b;
      check(ack_sda === (i == n - 1), $sformatf("read byte %0d of %0d: master %s expected", i, n,
                                                (i == n - 1) ? "NACK (SDA released)" : "ACK (SDA low)"));
    end
  endtask

  task automatic ee_random_read(input logic [11:0] addr, input int n);
    bit nk;
    int s0, p0;
    s0 = n_start; p0 = n_stop;
    i2c_wr(EE_W, 1'b1, 1'b0, nk);           check(!nk, "random read: control(W) NACKed");
    i2c_wr({4'h0, addr[11:8]}, 1'b0, 1'b0, nk); check(!nk, "random read: address high NACKed");
    i2c_wr(addr[7:0], 1'b0, 1'b0, nk);       check(!nk, "random read: address low NACKed");
    i2c_wr(EE_R, 1'b1, 1'b0, nk);           check(!nk, "random read: control(R) NACKed");
    ee_read_bytes(n);
    for (int i = 0; i < n; i++) begin
      logic [11:0] a;
      a = addr + 12'(i);
      check(rbuf[i] === exp_mem[a],
            $sformatf("random read 0x%03h: got 0x%02h expected 0x%02h", a, rbuf[i], exp_mem[a]));
    end
    exp_ptr = addr + 12'(n);
    check_at("I2C-29", n_start - s0 == 2 && n_stop - p0 == 1,
          $sformatf("random read: saw %0d START / %0d STOP, expected 2/1", n_start - s0, n_stop - p0));
  endtask

  task automatic ee_current_read(input int n);
    bit nk;
    i2c_wr(EE_R, 1'b1, 1'b0, nk);           check(!nk, "current read: control(R) NACKed");
    ee_read_bytes(n);
    for (int i = 0; i < n; i++) begin
      logic [11:0] a;
      a = exp_ptr + 12'(i);
      check(rbuf[i] === exp_mem[a],
            $sformatf("current read 0x%03h: got 0x%02h expected 0x%02h", a, rbuf[i], exp_mem[a]));
    end
    exp_ptr = exp_ptr + 12'(n);
  endtask

  task automatic check_meas(input int p, input string what);
    int exp_per, exp_hi;
    exp_per = 4 * (p + 1) * CLK_NS;
    exp_hi  = 2 * (p + 1) * CLK_NS;
    check(n_meas > 0, {what, ": no SCL period measured"});
    check(per_min == exp_per && per_max == exp_per,
          $sformatf("%s: SCL period %0d..%0d ns, expected %0d ns", what, per_min, per_max, exp_per));
    check(hi_min == exp_hi && hi_max == exp_hi,
          $sformatf("%s: SCL high %0d..%0d ns, expected %0d ns", what, hi_min, hi_max, exp_hi));
    $display("[%0t] INFO: %s: prescale %0d, SCL period %0d ns = %0d Hz (expected %0d Hz), %0d periods measured",
             $time, what, p, per_min, 1000000000 / per_min, 50000000 / (4 * (p + 1)), n_meas);
  endtask

  // ------------------------------------------------------------------ test sequence
  logic [31:0] d, isr;
  bit          nk;
  int          s0, p0;

  initial begin
    for (int i = 0; i < 4096; i++) exp_mem[i] = pattern(i);
    meas_reset();
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // ---- 1. reset values (regmap.py) and idle pins
    $display("[%0t] INFO: 1. reset values", $time);
    vp_regs();                                     // I2C-01 .. I2C-21
    item("I2C-01");
    expect_reg(A_CTRL,  32'h0,  "reset CTRL");
    item("I2C-03");
    expect_reg(A_PRESC, 32'd124, "reset PRESCALE");
    item("I2C-05");
    expect_reg(A_CMD,   32'h0,  "reset CMD");
    item("I2C-07");
    expect_reg(A_TX,    32'h0,  "reset TXDATA");
    item("I2C-09");
    expect_reg(A_RX,    32'h0,  "reset RXDATA");
    item("I2C-11");
    expect_reg(A_STAT,  32'h0,  "reset STATUS");
    item("I2C-13");
    expect_reg(A_IER,   32'h0,  "reset IER");
    item("I2C-15");
    expect_reg(A_ISR,   32'h0,  "reset ISR");
    item("I2C-16");
    expect_reg(12'h020, 32'h0,  "reserved 0x020");
    expect_reg(12'hFFC, 32'h0,  "reserved 0xFFC");
    item("I2C-36");
    check(scl_oe === 1'b0 && sda_oe === 1'b0, "reset: lines not released");
    item("I2C-37");
    check(irq === 1'b0, "reset: irq set");

    // ---- 2. register access: masks, byte strobes, RO/WO, reserved
    $display("[%0t] INFO: 2. register access", $time);
    item("I2C-02");
    apb_write(A_CTRL, 32'hFFFF_FFFE, 4'hF); expect_reg(A_CTRL, 32'h0, "CTRL write 0");
    apb_write(A_CTRL, 32'hFFFF_FFFF, 4'hE); expect_reg(A_CTRL, 32'h0, "CTRL pstrb[0]=0 ignored");
    apb_write(A_CTRL, 32'hFFFF_FFFF, 4'hF); expect_reg(A_CTRL, 32'h1, "CTRL mask");
    apb_write(A_CTRL, 32'h0, 4'hF);
    item("I2C-04");
    apb_write(A_PRESC, 32'hFFFF_FFFF, 4'hF); expect_reg(A_PRESC, 32'h0000_FFFF, "PRESCALE mask");
    item("I2C-21");
    apb_write(A_PRESC, 32'h0000_1234, 4'h1); expect_reg(A_PRESC, 32'h0000_FF34, "PRESCALE byte 0 only");
    apb_write(A_PRESC, 32'h0000_5678, 4'h2); expect_reg(A_PRESC, 32'h0000_5634, "PRESCALE byte 1 only");
    apb_write(A_PRESC, 32'h0000_007C, 4'h3); expect_reg(A_PRESC, 32'd124, "PRESCALE restore");
    item("I2C-08");
    apb_write(A_TX, 32'hFFFF_FFA5, 4'hF);    expect_reg(A_TX, 32'h0000_00A5, "TXDATA mask");
    apb_write(A_TX, 32'h0000_005A, 4'h2);    expect_reg(A_TX, 32'h0000_00A5, "TXDATA pstrb[0]=0 ignored");
    item("I2C-14");
    apb_write(A_IER, 32'hFFFF_FFFF, 4'hF);   expect_reg(A_IER, 32'h3, "IER mask");
    apb_write(A_IER, 32'h0, 4'hF);           expect_reg(A_IER, 32'h0, "IER clear");
    item("I2C-10");
    apb_write(A_RX, 32'hFFFF_FFFF, 4'hF);    expect_reg(A_RX, 32'h0, "RXDATA is RO");
    item("I2C-12");
    apb_write(A_STAT, 32'hFFFF_FFFF, 4'hF);  expect_reg(A_STAT, 32'h0, "STATUS is RO");
    item("I2C-38");
    apb_write(A_ISR, 32'hFFFF_FFFF, 4'hF);   expect_reg(A_ISR, 32'h0, "ISR write 1 when clear");
    item("I2C-16");
    apb_write(12'h020, 32'hFFFF_FFFF, 4'hF); expect_reg(12'h020, 32'h0, "reserved write ignored");

    // ---- 3. CMD ignored while disabled
    $display("[%0t] INFO: 3. CMD with i2c_en = 0", $time);
    item("I2C-34");
    apb_write(A_CMD, {24'h0, C_START}, 4'h1);
    expect_reg(A_CMD, 32'h0, "CMD reads 0");
    expect_reg(A_STAT, 32'h0, "CMD while disabled: not busy");
    repeat (1000) @(posedge clk);
    check(scl_oe === 1'b0 && sda_oe === 1'b0, "disabled: lines driven");
    expect_reg(A_ISR, 32'h0, "CMD while disabled: no done");

    // ---- 4. NACK on wrong address at 100 kHz (prescale 124), SCL frequency
    $display("[%0t] INFO: 4. wrong address at prescale 124", $time);
    chk_en = 1'b1;
    apb_write(A_CTRL, 32'h1, 4'h1);
    set_prescale(124);
    meas_reset();
    s0 = n_start; p0 = n_stop;
    item("I2C-26");
    apb_write(A_TX, {24'h0, BAD_W}, 4'h1);
    apb_write(A_CMD, {24'h0, C_START | C_WRITE}, 4'h1);
    wait_done(isr);
    check(isr[1:0] === 2'b11, $sformatf("wrong address: ISR=0x%0h expected nack+done", isr));
    expect_reg(A_STAT, 32'h6, "wrong address: STATUS bus_busy + rx_nack");
    item("I2C-33");
    expect_reg(A_STAT, 32'h6, "after START: bus_busy = 1");
    item("I2C-37");
    check(irq === 1'b0, "IER = 0: irq must stay low");
    item("I2C-22");
    check_meas(124, "100 kHz");
    item("I2C-26");
    check(u_ee.n_ctrl_nacked == 1, "EEPROM model did not see a foreign control byte");

    // ---- 5. IER gating and W1C
    $display("[%0t] INFO: 5. IER gating, W1C", $time);
    item("I2C-37");
    apb_write(A_IER, 32'h1, 4'h1); #1;
    check(irq === 1'b1, "done_ie: irq not set");
    item("I2C-38");
    apb_write(A_ISR, 32'h1, 4'h0); expect_reg(A_ISR, 32'h3, "W1C with pstrb[0]=0 ignored");
    apb_write(A_ISR, 32'h0, 4'h1); expect_reg(A_ISR, 32'h3, "ISR write 0 does not clear");
    apb_write(A_ISR, 32'h3, 4'hE); expect_reg(A_ISR, 32'h3, "W1C 3 with pstrb = 1110 ignored");
    item("I2C-37");
    for (int ie = 0; ie < 4; ie++) begin
      apb_write(A_IER, ie, 4'h1); #1;
      check(irq === (ie != 0), $sformatf("ISR=3 IER=%0d: irq=%b", ie, irq));
    end
    apb_write(A_IER, 32'h1, 4'h1);
    item("I2C-38");
    apb_write(A_ISR, 32'h1, 4'h1); expect_reg(A_ISR, 32'h2, "W1C done only");
    item("I2C-37");
    check(irq === 1'b0, "done cleared, nack_ie = 0: irq must be low");
    apb_write(A_IER, 32'h2, 4'h1); #1;
    check(irq === 1'b1, "nack_ie: irq not set");
    apb_write(A_IER, 32'h0, 4'h1); #1;
    check(irq === 1'b0, "IER = 0: irq must be low");
    apb_write(A_IER, 32'h2, 4'h1);
    item("I2C-38");
    apb_write(A_ISR, 32'h2, 4'h1); expect_reg(A_ISR, 32'h0, "W1C nack");
    check(irq === 1'b0, "nack cleared: irq must be low");
    apb_write(A_IER, 32'h0, 4'h1);
    item("I2C-23");
    i2c_cmd(C_STOP, isr);
    check(scl_bus === 1'b1 && sda_bus === 1'b1, "after STOP: bus idle (SCL and SDA high)");
    check(n_start - s0 == 1 && n_stop - p0 == 1, "wrong address: START/STOP count");
    item("I2C-33");
    expect_reg(A_STAT, 32'h2, "after STOP: bus_busy 0, rx_nack kept");

    // ---- 6. small prescale: SCL frequency, byte write + ACK polling, random read
    $display("[%0t] INFO: 6. byte write / random read at prescale 4", $time);
    set_prescale(4);
    meas_reset();
    item("I2C-27");
    wbuf[0] = 8'h3C;
    ee_write(12'h123, 1, 1'b1);
    item("I2C-22");
    check_meas(4, "2.5 MHz");
    item("I2C-25");
    expect_reg(A_STAT, 32'h0, "after ACK poll: rx_nack 0, bus free");
    item("I2C-27");
    ee_random_read(12'h123, 1);
    item("I2C-28");
    ee_random_read(12'h120, 6);                        // around the written byte

    // ---- 7. page write with 32-byte page wrap
    $display("[%0t] INFO: 7. page write with wrap", $time);
    item("I2C-27");
    for (int i = 0; i < 4; i++) wbuf[i] = 8'hC0 + 8'(i);
    ee_write(12'h05E, 4, 1'b1);                         // 0x5E, 0x5F, wrap to 0x40, 0x41
    check(exp_mem[12'h040] === 8'hC2 && exp_mem[12'h041] === 8'hC3, "tb page wrap model");
    ee_random_read(12'h05C, 6);                         // 0x5C..0x61: 0x60/0x61 untouched
    ee_random_read(12'h03F, 4);                         // 0x3F..0x42
    for (int i = 0; i < 32; i++) wbuf[i] = 8'(i * 5 + 1);
    ee_write(12'h200, 32, 1'b1);                        // full page
    ee_random_read(12'h1FF, 34);

    // ---- 8. current-address read and sequential read with 0xFFF -> 0x000 rollover
    $display("[%0t] INFO: 8. current-address and sequential reads", $time);
    item("I2C-28");
    ee_random_read(12'h300, 2);
    ee_current_read(3);                                 // continues at 0x302
    item("I2C-30");
    ee_random_read(12'hFFD, 2);
    ee_current_read(3);                                 // 0xFFF, 0x000, 0x001
    // Dummy write (address set, STOP), then current-address read.
    item("I2C-28");
    i2c_wr(EE_W, 1'b1, 1'b0, nk); check(!nk, "dummy write control NACKed");
    i2c_wr(8'h00, 1'b0, 1'b0, nk);
    i2c_wr(8'h7A, 1'b0, 1'b1, nk); check(!nk, "dummy write address NACKed");
    exp_ptr = 12'h07A;
    ee_current_read(2);
    expect_reg(A_STAT, 32'h0, "after reads: STATUS");

    // ---- 9. wrong address at small prescale, done/nack with irq enabled
    $display("[%0t] INFO: 9. wrong address with IER enabled", $time);
    item("I2C-26");
    apb_write(A_IER, 32'h3, 4'h1);
    apb_write(A_TX, {24'h0, BAD_W | 8'h1}, 4'h1);
    apb_write(A_CMD, {24'h0, C_START | C_WRITE | C_STOP}, 4'h1);
    @(posedge irq);
    apb_read(A_ISR, isr);
    check(isr[1] === 1'b1, "nack must be set before done");
    wait_done(isr);
    check(isr[1:0] === 2'b11, "wrong address read: ISR");
    expect_reg(A_STAT, 32'h2, "wrong address read: rx_nack, bus free (STOP generated)");
    item("I2C-38");
    apb_write(A_ISR, 32'h3, 4'h1); #1;
    check(irq === 1'b0, "irq not cleared by W1C");
    // A good write afterwards clears rx_nack.
    item("I2C-25");
    i2c_wr(EE_W, 1'b1, 1'b1, nk);
    check(!nk, "good address after NACK");
    expect_reg(A_STAT, 32'h0, "rx_nack cleared by ACK");
    apb_write(A_IER, 32'h0, 4'h1);
    apb_write(A_ISR, 32'h3, 4'h1);

    // ---- 10. ignored commands: read+write, pstrb[0]=0, no action bit, while busy
    $display("[%0t] INFO: 10. ignored commands", $time);
    item("I2C-35");
    s0 = n_start; p0 = n_stop;
    apb_write(A_CMD, {24'h0, C_START | C_WRITE | C_READ}, 4'h1);
    expect_reg(A_STAT, 32'h0, "CMD read+write ignored");
    apb_write(A_CMD, {24'h0, C_START | C_WRITE}, 4'hE);
    expect_reg(A_STAT, 32'h0, "CMD pstrb[0]=0 ignored");
    apb_write(A_CMD, {24'h0, C_NACK}, 4'h1);
    expect_reg(A_STAT, 32'h0, "CMD with no action bit ignored");
    repeat (200) @(posedge clk);
    expect_reg(A_ISR, 32'h0, "ignored commands: no done");
    check(n_start == s0 && n_stop == p0, "ignored commands touched the bus");
    apb_write(A_TX, {24'h0, EE_W}, 4'h1);
    apb_write(A_CMD, {24'h0, C_START | C_WRITE}, 4'h1);
    apb_write(A_CMD, {24'h0, C_STOP}, 4'h1);           // while busy: ignored
    wait_done(isr);
    apb_write(A_ISR, 32'h3, 4'h1);
    repeat (300) @(posedge clk);
    expect_reg(A_ISR, 32'h0, "CMD while busy: no second done");
    expect_reg(A_STAT, 32'h4, "CMD while busy: no STOP, bus still busy");
    check(n_start - s0 == 1 && n_stop == p0, "CMD while busy produced a STOP");
    i2c_cmd(C_STOP, isr);
    expect_reg(A_STAT, 32'h0, "STOP alone: bus free");

    // ---- 11. bus_busy from the bus lines, START alone, i2c_en = 0 releases lines
    $display("[%0t] INFO: 11. bus_busy and i2c_en = 0", $time);
    item("I2C-33");
    i2c_cmd(C_START, isr);
    expect_reg(A_STAT, 32'h4, "START alone: bus_busy");
    check(scl_oe === 1'b1 && sda_oe === 1'b1, "after START alone: SCL and SDA held low");
    item("I2C-34");
    chk_en = 1'b0;                                      // release of both lines at once
    apb_write(A_CTRL, 32'h0, 4'h1);                     // released one clock after the write
    @(posedge clk); #1;
    check(scl_oe === 1'b0 && sda_oe === 1'b0, "i2c_en = 0 did not release the lines");
    check(scl_bus === 1'b1 && sda_bus === 1'b1, "bus not idle after release");
    repeat (5) @(posedge clk);
    expect_reg(A_STAT, 32'h0, "release seen as STOP: bus_busy 0");
    // Another device on the bus: bus_busy follows the lines while the master is disabled.
    item("I2C-33");
    tb_sda_low = 1'b1; #500; tb_scl_low = 1'b1; #500;
    expect_reg(A_STAT, 32'h4, "external START: bus_busy");
    tb_scl_low = 1'b0; #500; tb_sda_low = 1'b0; #500;
    expect_reg(A_STAT, 32'h0, "external STOP: bus_busy cleared");
    item("I2C-34");
    // Abort in the middle of a byte at prescale 124.
    apb_write(A_CTRL, 32'h1, 4'h1);
    set_prescale(124);
    apb_write(A_TX, {24'h0, EE_W}, 4'h1);
    apb_write(A_CMD, {24'h0, C_START | C_WRITE}, 4'h1);
    #(30000);
    expect_reg(A_STAT, 32'h5, "mid-byte: busy and bus_busy");
    apb_write(A_CTRL, 32'h0, 4'h1);
    @(posedge clk); #1;
    check(scl_oe === 1'b0 && sda_oe === 1'b0, "abort: lines not released");
    repeat (5) @(posedge clk);
    d = 32'h0;
    apb_read(A_STAT, d);
    check(d[0] === 1'b0, "abort: still busy");
    repeat (2000) @(posedge clk);
    check(scl_oe === 1'b0 && sda_oe === 1'b0, "abort: lines driven again");
    expect_reg(A_ISR, 32'h0, "abort: no done");
    // A STOP from the bus monitor's point of view may or may not have been seen;
    // finish the bus cleanly with an external STOP so bus_busy is 0.
    tb_sda_low = 1'b1; #500; tb_sda_low = 1'b0; #500;
    expect_reg(A_STAT, 32'h0, "abort: bus free");

    // ---- 12. recovery after disable, then a last write/read at prescale 1
    $display("[%0t] INFO: 12. recovery", $time);
    apb_write(A_CTRL, 32'h1, 4'h1);
    set_prescale(4);
    chk_en = 1'b1;
    meas_reset();
    item("I2C-27");
    wbuf[0] = 8'h99; wbuf[1] = 8'h66;
    ee_write(12'hABC, 2, 1'b1);
    ee_random_read(12'hABC, 2);

    item("I2C-22");
    check_meas(4, "after recovery");
    item("I2C-36");
    check(pin_bad == 0, $sformatf("scl_o / sda_o not 0 on %0d clocks", pin_bad));
    $display("[%0t] INFO: %0d START, %0d STOP, %0d EEPROM write cycles",
             $time, n_start, n_stop, u_ee.n_write_cycles);
    vplan_pkg::report(VP_BLOCK, VP_N);
    $finish;
  end

  initial begin
    #(60_000_000);
    $display("ERROR: global timeout");
    $display("TEST FAILED");
    $finish;
  end

endmodule
