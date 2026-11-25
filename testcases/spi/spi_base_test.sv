// SPI base test
class spi_base_test;
  string            name = "spi_base_test";
  virtual apb_if    apb_vif;
  virtual spi_if    spi_vif;
  spi_environment   env;
  apb_stimulus      stim;       // APB side (name used by apb_class_tasks.svh)
  spi_stimulus      sstim;      // slave side
  spi_scoreboard    sb;
  spi_cfg           cfg;
  int unsigned      seen;       // frames already counted by wait_frames()

  // Register offsets (doc/spec/regmap.py)
  localparam bit [11:0] CTRL   = 12'h000;
  localparam bit [11:0] CLKDIV = 12'h004;
  localparam bit [11:0] CS     = 12'h008;
  localparam bit [11:0] STATUS = 12'h00C;
  localparam bit [11:0] TXDATA = 12'h010;
  localparam bit [11:0] RXDATA = 12'h014;
  localparam bit [11:0] IER    = 12'h018;
  localparam bit [11:0] ISR    = 12'h01C;
  // CTRL bits
  localparam bit [31:0] C_EN   = 32'h01;
  localparam bit [31:0] C_CPOL = 32'h02;
  localparam bit [31:0] C_CPHA = 32'h04;
  localparam bit [31:0] C_LSB  = 32'h08;
  // STATUS bits
  localparam bit [31:0] S_BUSY    = 32'h01;
  localparam bit [31:0] S_TXFULL  = 32'h02;
  localparam bit [31:0] S_TXEMPTY = 32'h04;
  localparam bit [31:0] S_RXFULL  = 32'h08;
  localparam bit [31:0] S_RXEMPTY = 32'h10;
  // ISR / IER bits
  localparam bit [31:0] I_DONE = 32'h01;
  localparam bit [31:0] I_OVR  = 32'h02;

  `include "apb_class_tasks.svh"
  `include "vplan/vp_spi.svh"

  function new();
  endfunction

  virtual function void build();
    env = new(apb_vif, spi_vif);
    env.build();
    stim  = env.apb_stim;
    sstim = env.stim;
    sb    = env.sb;
    cfg   = env.cfg;
  endfunction

  task flush();
    env.flush();
  endtask

  // Checks while reset is still active (overridden by spi_reg_test)
  virtual task during_reset();
  endtask

  virtual task run_scenario();
    vp_regs();
  endtask

  task run_test();
    $display("%0t: [%s] start", $time, name);
    build();
    env.run();
    during_reset();
    wait (apb_vif.rst_n === 1'b1);
    clks(2);
    run_scenario();
    wait_idle();
    flush();
    sb.report();
    $display("%0t: [%s] End simulation", $time, name);
    vplan_pkg::report(VP_BLOCK, VP_N, "", 1'b1);
    $finish;
  endtask

  // ---------------------------------------------------------------- helpers
  function bit [31:0] mode_bits(input bit cpol, input bit cpha, input bit lsb);
    return (cpol ? C_CPOL : 0) | (cpha ? C_CPHA : 0) | (lsb ? C_LSB : 0);
  endfunction

  function void irq_is(input bit exp, input string what);
    check(apb_vif.irq[0] === exp, $sformatf("%s: irq_spi_o = %b, expected %b", what, apb_vif.irq[0], exp));
  endfunction

  task irq_check(input bit exp, input string what);
    #1;
    irq_is(exp, what);
  endtask

  // Clock edges counted on the SPI interface. Use wclk() instead of clks()
  // inside a fork: clks() sends an idle packet to the APB driver.
  task wclk(input int unsigned n);
    repeat (n) @(posedge spi_vif.clk);
    #1;
  endtask

  // The byte the slave returns in one of the next frames
  task slave(input bit [7:0] d);
    spi_packet p = new();
    p.data = d;
    sstim.send_pkt(p);
  endtask

  // Mode, clock divider, flags cleared, with CS high; then CS low. The
  // slave model takes the mode while CS is high (as a real slave would).
  task setup_mode(input bit cpol, input bit cpha, input bit lsb, input int unsigned dv,
                  input bit cs_low = 1'b1);
    write(CS, 32'h1);
    write(CTRL, mode_bits(cpol, cpha, lsb));
    write(CLKDIV, dv);
    write(ISR, I_DONE | I_OVR);
    if (cs_low) write(CS, 32'h0);
  endtask

  // Frames reported by the monitor since the last wait_frames()
  function int unsigned frame_count();
    return sb.n_frames - seen;
  endfunction

  // Wait until n more frames have ended
  task wait_frames(input int unsigned n);
    int unsigned lim = n * (16 * (cfg.div + 1) + 8) + 60;
    while (frame_count() < n && lim > 0) begin
      wclk(1);
      lim--;
    end
    check(frame_count() >= n, $sformatf("monitor saw %0d frames, expected %0d", frame_count(), n));
    seen += n;
  endtask

  // Wait until no frame is in progress or about to start
  task wait_idle(input int unsigned max_clks = 1_000_000);
    while (max_clks > 0 && !sb.quiet()) begin
      wclk(1);
      max_clks--;
    end
    wclk(4);
    seen = sb.n_frames;
  endtask

  // One burst: the slave returns din, the master sends dout (all bytes in
  // the TX FIFO before spi_en is set, so the frames are back to back). Checks
  // STATUS, ISR.done and every RXDATA byte. The scoreboard checks the frames
  // (MOSI bytes, timing) and the reads too.
  task xfer(input bit cpol, input bit cpha, input bit lsb, input int unsigned dv,
            input bit [7:0] dout[$], input bit [7:0] din[$], input string what);
    bit [31:0] m = mode_bits(cpol, cpha, lsb);
    $display("%0t: [%s] %s: mode %0d%s div=%0d, %0d bytes", $time, name, what, {cpol, cpha},
             lsb ? " LSB" : "", dv, dout.size());
    foreach (din[i]) slave(din[i]);
    setup_mode(cpol, cpha, lsb, dv);
    foreach (dout[i]) write(TXDATA, {24'd0, dout[i]});
    write(CTRL, m | C_EN);
    wait_frames(dout.size());
    clks(2);
    rd_check(STATUS, S_TXEMPTY | ((dout.size() == 16) ? S_RXFULL : 32'h0),
             $sformatf("%s: STATUS after the burst", what));
    rd_check(ISR, I_DONE, $sformatf("%s: ISR.done after the burst", what));
    foreach (din[i])
      rd_check(RXDATA, {24'd0, din[i]}, $sformatf("%s: RXDATA byte %0d", what, i));
    write(CTRL, m);
    write(CS, 32'h1);
    check(spi_vif.sclk === cpol, $sformatf("%s: SCLK idle level %b, CPOL %b", what, spi_vif.sclk, cpol));
  endtask

  // Burst of n random bytes
  task xfer_rand(input bit cpol, input bit cpha, input bit lsb, input int unsigned dv,
                 input int unsigned n, input string what);
    bit [7:0] dout[$], din[$];
    for (int i = 0; i < n; i++) begin
      dout.push_back(8'($urandom));
      din.push_back(8'($urandom));
    end
    xfer(cpol, cpha, lsb, dv, dout, din, what);
  endtask
endclass
