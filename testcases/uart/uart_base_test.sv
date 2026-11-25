// UART base test
class uart_base_test;
  string            name = "uart_base_test";
  virtual apb_if    apb_vif;
  virtual uart_if   uart_vif;
  uart_environment  env;
  apb_stimulus      stim;       // APB side (name used by apb_class_tasks.svh)
  uart_stimulus     ustim;      // serial side
  uart_scoreboard   sb;
  int unsigned      tx_seen;    // TX frames already counted by wait_tx()

  // Register offsets (doc/spec/regmap.py)
  localparam bit [11:0] CTRL   = 12'h000;
  localparam bit [11:0] BAUD   = 12'h004;
  localparam bit [11:0] STATUS = 12'h008;
  localparam bit [11:0] TXDATA = 12'h00C;
  localparam bit [11:0] RXDATA = 12'h010;
  localparam bit [11:0] IER    = 12'h014;
  localparam bit [11:0] ISR    = 12'h018;
  // CTRL bits
  localparam bit [31:0] C_TXEN  = 32'h01;
  localparam bit [31:0] C_RXEN  = 32'h02;
  localparam bit [31:0] C_EVEN  = 32'h04;
  localparam bit [31:0] C_ODD   = 32'h08;
  localparam bit [31:0] C_STOP2 = 32'h10;
  localparam bit [31:0] C_LOOP  = 32'h20;
  // STATUS bits
  localparam bit [31:0] S_TXFULL  = 32'h01;
  localparam bit [31:0] S_TXEMPTY = 32'h02;
  localparam bit [31:0] S_RXFULL  = 32'h04;
  localparam bit [31:0] S_RXEMPTY = 32'h08;
  localparam bit [31:0] S_TXBUSY  = 32'h10;
  localparam bit [31:0] S_RXBUSY  = 32'h20;
  // ISR / IER bits
  localparam bit [31:0] I_TXEMPTY = 32'h01;
  localparam bit [31:0] I_RXNE    = 32'h02;
  localparam bit [31:0] I_PERR    = 32'h04;
  localparam bit [31:0] I_FERR    = 32'h08;
  localparam bit [31:0] I_OVR     = 32'h10;
  localparam bit [31:0] I_TXOVF   = 32'h20;

  `include "apb_class_tasks.svh"
  `include "vplan/vp_uart.svh"

  function new();
  endfunction

  virtual function void build();
    env = new(apb_vif, uart_vif);
    env.build();
    stim  = env.apb_stim;
    ustim = env.stim;
    sb    = env.sb;
  endfunction

  task flush();
    env.flush();
  endtask

  // Checks while reset is still active (overridden by uart_reg_test)
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
  function bit [31:0] ctrl_par(input bit [1:0] p);
    return {28'd0, p, 2'b00};
  endfunction

  function void irq_is(input bit exp, input string what);
    check(apb_vif.irq[0] === exp, $sformatf("%s: irq_uart_o = %b, expected %b", what, apb_vif.irq[0], exp));
  endfunction

  task irq_check(input bit exp, input string what);
    #1;
    irq_is(exp, what);
  endtask

  // One frame on uart_rx_i; returns when the last stop bit has been sent
  task send_frame(input bit [7:0] d, input int unsigned div, input bit [1:0] par, input bit stop2,
                  input bit bad_par = 1'b0, input bit [1:0] bad_stop = 2'b00);
    uart_packet p = new();
    p.kind = UART_FRAME; p.data = d; p.div = div; p.par = par; p.stop2 = stop2;
    p.bad_par = bad_par; p.bad_stop = bad_stop;
    ustim.send(p);
  endtask

  task send_ok(input bit [7:0] d, input int unsigned div, input bit [1:0] par, input bit stop2);
    send_frame(d, div, par, stop2);
  endtask

  task send_glitch(input int unsigned n);
    uart_packet p = new();
    p.kind = UART_GLITCH; p.glitch_clks = n;
    ustim.send(p);
  endtask

  task send_skew(input bit [7:0] d, input int unsigned div, input int skew);
    uart_packet p = new();
    p.kind = UART_SKEW; p.data = d; p.div = div; p.skew = skew;
    ustim.send(p);
  endtask

  // Clock edges counted on the UART interface. Use wclk() instead of clks()
  // inside a fork: clks() sends an idle packet to the APB driver, and two
  // threads must not share the APB stimulus.
  task wclk(input int unsigned n);
    repeat (n) @(posedge uart_vif.clk);
    #1;
  endtask

  // TX frames reported by the monitor since the last wait_tx()
  function int unsigned tx_count();
    return sb.n_tx_frames - tx_seen;
  endfunction

  // Wait until n more TX frames have ended (at most max_bits bit periods)
  task wait_tx(input int unsigned n, input int unsigned max_bits);
    int unsigned lim = max_bits * (sb.cfg.div + 1) + 20;
    while (tx_count() < n && lim > 0) begin
      wclk(1);
      lim--;
    end
    check(tx_count() >= n, $sformatf("monitor saw %0d TX frames, expected %0d", tx_count(), n));
    tx_seen += n;
  endtask

  // Wait until the scoreboard has received every frame sent on uart_rx_i
  // (the monitor reports a frame a few clocks after its last stop bit)
  task rx_wait(input int unsigned max_clks = 100_000);
    while (max_clks > 0 && (sb.rx_busy_n != 0 || ustim.pkt_q.size() != 0)) begin
      wclk(1);
      max_clks--;
    end
    check(sb.rx_busy_n == 0, "frame on uart_rx_i not reported by the monitor");
    wclk(1);
  endtask

  // Wait until no frame is in progress or waiting in the TX FIFO
  task wait_idle(input int unsigned max_clks = 2_000_000);
    while (max_clks > 0 && (sb.tx_busy_n != 0 || sb.rx_busy_n != 0 || ustim.pkt_q.size() != 0 ||
                            (sb.cfg.tx_en && sb.txq.size() != 0))) begin
      wclk(1);
      max_clks--;
    end
    wclk(8);
  endtask
endclass
