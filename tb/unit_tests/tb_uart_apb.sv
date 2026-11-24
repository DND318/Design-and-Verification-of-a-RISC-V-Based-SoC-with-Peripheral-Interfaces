// Directed, self-checking testbench for uart_apb.
// The serial side is checked with an independent UART line model written
// from the frame format (start, 8 data LSB first, optional parity, 1/2 stop):
//   - line encoder  : drives uart_rx_i with any baud/parity/stop setting and
//                     can inject parity errors, bad stop bits and glitches;
//   - line decoder  : watches uart_tx_o, samples every bit at its start,
//                     middle and end, and checks the format and bit period.
// The APB side uses apb_write / apb_read tasks (SETUP then ACCESS).
// Checks are grouped by vplan item (doc/vplan, sheet UART); the log ends
// with a PASS / FAIL / NOT RUN line per item, then "TEST PASSED" or
// "TEST FAILED" for scripts/check_log.sh.
`timescale 1ns/1ps
module tb_uart_apb;

  localparam int CLK_NS = 20;  // 50 MHz

  // Register offsets (regmap.py)
  localparam logic [11:0] CTRL   = 12'h000;
  localparam logic [11:0] BAUD   = 12'h004;
  localparam logic [11:0] STATUS = 12'h008;
  localparam logic [11:0] TXDATA = 12'h00C;
  localparam logic [11:0] RXDATA = 12'h010;
  localparam logic [11:0] IER    = 12'h014;
  localparam logic [11:0] ISR    = 12'h018;

  // CTRL bits
  localparam logic [31:0] C_TXEN  = 32'h01;
  localparam logic [31:0] C_RXEN  = 32'h02;
  localparam logic [31:0] C_EVEN  = 32'h04;
  localparam logic [31:0] C_ODD   = 32'h08;
  localparam logic [31:0] C_STOP2 = 32'h10;
  localparam logic [31:0] C_LOOP  = 32'h20;

  // STATUS bits
  localparam logic [31:0] S_TXFULL  = 32'h01;
  localparam logic [31:0] S_TXEMPTY = 32'h02;
  localparam logic [31:0] S_RXFULL  = 32'h04;
  localparam logic [31:0] S_RXEMPTY = 32'h08;
  localparam logic [31:0] S_TXBUSY  = 32'h10;
  localparam logic [31:0] S_RXBUSY  = 32'h20;

  // ISR / IER bits
  localparam logic [31:0] I_TXEMPTY = 32'h01;
  localparam logic [31:0] I_RXNE    = 32'h02;
  localparam logic [31:0] I_PERR    = 32'h04;
  localparam logic [31:0] I_FERR    = 32'h08;
  localparam logic [31:0] I_OVR     = 32'h10;
  localparam logic [31:0] I_TXOVF   = 32'h20;

  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic        psel = 1'b0, penable = 1'b0, pwrite = 1'b0;
  logic [11:0] paddr = '0;
  logic [31:0] pwdata = '0;
  logic [3:0]  pstrb = '0;
  logic [31:0] prdata;
  logic        pready, pslverr;
  logic        uart_tx;
  logic        rx_line = 1'b1;
  logic        irq;


  always #(CLK_NS / 2) clk = ~clk;

  uart_apb dut (
    .clk_i(clk), .rst_ni(rst_n),
    .psel_i(psel), .penable_i(penable), .pwrite_i(pwrite), .paddr_i(paddr),
    .pwdata_i(pwdata), .pstrb_i(pstrb), .prdata_o(prdata), .pready_o(pready),
    .pslverr_o(pslverr),
    .uart_tx_o(uart_tx), .uart_rx_i(rx_line), .irq_uart_o(irq)
  );

  // ------------------------------------------------------------------ helpers
`include "apb_common.svh"
`include "vplan/vp_uart.svh"

  task automatic irq_check(input bit exp, input string what);
    #1;
    check(irq === exp, $sformatf("%s: irq=%b expected %b", what, irq, exp));
  endtask

  // ------------------------------------------------------------------ line encoder (drives uart_rx_i)
  function automatic bit par_bit(input logic [7:0] d, input logic [1:0] par);
    // even: number of ones in data+parity is even; odd: it is odd
    int ones = 0;
    for (int i = 0; i < 8; i++) ones += int'(d[i]);
    if (par == 2'b01) return bit'(ones % 2);
    else              return bit'((ones + 1) % 2);
  endfunction

  // bad_stop[0] / bad_stop[1]: drive the first / second stop bit as 0
  task automatic uart_send(input logic [7:0] d, input int div, input logic [1:0] par, input bit stop2,
                           input bit bad_par, input logic [1:0] bad_stop);
    int bt = (div + 1) * CLK_NS;
    rx_line = 1'b0;
    #(bt);
    for (int i = 0; i < 8; i++) begin
      rx_line = d[i];
      #(bt);
    end
    if (par != 2'b00) begin
      rx_line = par_bit(d, par) ^ bad_par;
      #(bt);
    end
    rx_line = !bad_stop[0];
    #(bt);
    if (stop2) begin
      rx_line = !bad_stop[1];
      #(bt);
    end
    rx_line = 1'b1;
  endtask

  task automatic send_ok(input logic [7:0] d, input int div, input logic [1:0] par, input bit stop2);
    uart_send(d, div, par, stop2, 1'b0, 2'b00);
  endtask

  // ------------------------------------------------------------------ line decoder (watches uart_tx_o)
  int         mon_div   = 433;
  logic [1:0] mon_par   = 2'b00;
  bit         mon_stop2 = 1'b0;
  logic [7:0] tx_got [$];
  time        tx_t0  [$];
  bit         tx_idle_check = 1'b0;  // 1: uart_tx_o must not move at all

  // Sample bit k of a frame that started at t0 at three points.
  task automatic get_bit(input time t0, input int k, input int bt, output logic v, output bit stable);
    logic s0, s1, s2;
    time tgt, tb0, bt_t, hc_t;
    int  hc = CLK_NS / 2;
    bt_t = time'(longint'(bt));
    hc_t = time'(longint'(hc));
    tb0  = t0 + time'(longint'(k)) * bt_t;
    tgt = tb0 + hc_t;                         #(tgt - $time); s0 = uart_tx;
    tgt = tb0 + bt_t / 2;                     #(tgt - $time); s1 = uart_tx;
    tgt = tb0 + bt_t - hc_t;                  #(tgt - $time); s2 = uart_tx;
    v = s1;
    stable = (s0 === s1) && (s1 === s2);
  endtask

  initial begin : tx_decoder
    time t0;
    int bt, k;
    logic v;
    bit st;
    logic [7:0] d;
    logic [1:0] par;
    bit stop2;
    forever begin
      @(negedge uart_tx);
      t0 = $time;
      bt = (mon_div + 1) * CLK_NS;
      par = mon_par;
      stop2 = mon_stop2;
      get_bit(t0, 0, bt, v, st);
      check(v === 1'b0 && st, $sformatf("decoder: bad start bit (v=%b stable=%b)", v, st));
      for (k = 0; k < 8; k++) begin
        get_bit(t0, k + 1, bt, v, st);
        check(st, $sformatf("decoder: data bit %0d not stable for one bit period", k));
        d[k] = v;
      end
      k = 9;
      if (par != 2'b00) begin
        get_bit(t0, k, bt, v, st);
        check(st && v === par_bit(d, par), $sformatf("decoder: parity bit %b for data %h (mode %b)", v, d, par));
        k++;
      end
      get_bit(t0, k, bt, v, st);
      check(st && v === 1'b1, "decoder: stop bit 1 is not 1");
      if (stop2) begin
        k++;
        get_bit(t0, k, bt, v, st);
        check(st && v === 1'b1, "decoder: stop bit 2 is not 1");
      end
      tx_got.push_back(d);
      tx_t0.push_back(t0);
    end
  end

  always @(uart_tx) begin
    if (tx_idle_check) check(1'b0, "uart_tx_o moved while it must stay 1");
  end

  task automatic mon_cfg(input int div, input logic [1:0] par, input bit stop2);
    mon_div = div; mon_par = par; mon_stop2 = stop2;
  endtask

  // Wait until the decoder has n bytes (or fail after max_bits bit periods).
  task automatic wait_tx(input int n, input int max_bits);
    int lim = max_bits * (mon_div + 1);
    while (tx_got.size() < n && lim > 0) begin
      @(posedge clk);
      lim--;
    end
    check(tx_got.size() >= n, $sformatf("decoder got %0d bytes, expected %0d", tx_got.size(), n));
  endtask

  task automatic expect_tx(input logic [7:0] exp, input string what);
    logic [7:0] g;
    if (tx_got.size() == 0) begin
      check(1'b0, $sformatf("%s: no byte decoded, expected %h", what, exp));
    end else begin
      g = tx_got.pop_front();
      void'(tx_t0.pop_front());
      check(g === exp, $sformatf("%s: decoded %h expected %h", what, g, exp));
    end
  endtask

  function automatic int frame_bits(input logic [1:0] par, input bit stop2);
    return 10 + (par != 2'b00 ? 1 : 0) + (stop2 ? 1 : 0);
  endfunction

  function automatic logic [31:0] ctrl_par(input logic [1:0] par);
    return {28'd0, par, 2'b00};
  endfunction

  // ------------------------------------------------------------------ tests
  logic [7:0]  bytes [$];
  int          div;

  // TX: send a few bytes with one setting and check them on the line
  task automatic tx_case(input int dv, input logic [1:0] p, input bit s2, input int nbytes);
    logic [7:0] b [$];
    time t_prev;
    int fb, sp;
    mon_cfg(dv, p, s2);
    wr(BAUD, dv);
    wr(CTRL, C_TXEN | ctrl_par(p) | (s2 ? C_STOP2 : 32'd0));
    for (int i = 0; i < nbytes; i++) begin
      b.push_back(8'($urandom));
      if (i == 0) b[0] = 8'hA5 ^ 8'(dv);
    end
    foreach (b[i]) apb_write(TXDATA, {24'hFFFFFF, b[i]}, 4'h1);
    wait_tx(nbytes, (nbytes + 1) * 13 + 20);
    fb = frame_bits(p, s2);
    sp = fb * (dv + 1) * CLK_NS;
    for (int i = 0; i < nbytes; i++) begin
      if (i > 0 && tx_t0.size() > 0) begin
        // back-to-back frames: next start edge exactly one frame later
        check(tx_t0[0] - t_prev == time'(longint'(sp)),
              $sformatf("TX div=%0d par=%b stop2=%b: frame spacing %0t", dv, p, s2, tx_t0[0] - t_prev));
      end
      if (tx_t0.size() > 0) t_prev = tx_t0[0];
      expect_tx(b[i], $sformatf("TX div=%0d par=%b stop2=%b byte %0d", dv, p, s2, i));
    end
    clks(4);
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "STATUS after TX done");
  endtask

  // RX: send a few bytes on the line and read them back
  task automatic rx_case(input int dv, input logic [1:0] p, input bit s2, input int nbytes);
    logic [7:0] b [$];
    wr(BAUD, dv);
    wr(CTRL, C_RXEN | ctrl_par(p) | (s2 ? C_STOP2 : 32'd0));
    for (int i = 0; i < nbytes; i++) b.push_back(8'($urandom));
    b[0] = 8'h5A ^ 8'(dv);
    foreach (b[i]) send_ok(b[i], dv, p, s2);   // back-to-back on the line
    clks(4);
    rd_mask(STATUS, S_RXEMPTY | S_RXBUSY, 32'h0, $sformatf("RX div=%0d: STATUS not empty", dv));
    foreach (b[i]) rd_check(RXDATA, {24'd0, b[i]}, $sformatf("RX div=%0d par=%b stop2=%b byte %0d", dv, p, s2, i));
    rd_mask(STATUS, S_RXEMPTY, S_RXEMPTY, "RX FIFO empty after reads");
    rd_check(ISR, I_TXEMPTY, $sformatf("RX div=%0d par=%b: no error flag", dv, p));
  endtask

  // TX: send fixed bytes with one setting; the decoder checks every bit
  task automatic tx_fixed(input int dv, input logic [1:0] p, input bit s2,
                          input logic [7:0] b0, input logic [7:0] b1);
    mon_cfg(dv, p, s2);
    wr(BAUD, dv);
    wr(CTRL, C_TXEN | ctrl_par(p) | (s2 ? C_STOP2 : 32'd0));
    apb_write(TXDATA, {24'd0, b0}, 4'h1);
    apb_write(TXDATA, {24'd0, b1}, 4'h1);
    wait_tx(2, 2 * 13 + 20);
    expect_tx(b0, $sformatf("TX div=%0d par=%b byte %h", dv, p, b0));
    expect_tx(b1, $sformatf("TX div=%0d par=%b byte %h", dv, p, b1));
    clks(4);
    wr(CTRL, 32'h0);
  endtask

  // RX: frame whose bit edges are moved by +/- skew clocks (alternating)
  task automatic uart_send_skew(input logic [7:0] d, input int dv, input int skew);
    int bt = (dv + 1) * CLK_NS;
    int len;
    logic [9:0] f = {1'b1, d, 1'b0};
    for (int i = 0; i < 10; i++) begin
      rx_line = f[i];
      len = (i % 2 == 0) ? bt + skew * CLK_NS : bt - skew * CLK_NS;
      #(len);
    end
    rx_line = 1'b1;
    #(bt);
  endtask

  initial begin
    $display("tb_uart_apb: start");
    clks(3);
    #1;
    item("UART-01");
    check(uart_tx === 1'b1 && irq === 1'b0, "outputs during reset");
    rst_n = 1'b1;
    clks(2);

    // ---------------------------------------------------------------- T1 reset values
    vp_regs();                                    // UART-01 .. UART-19
    item("UART-01");
    $display("T1 reset values");
    rd_check(CTRL,   32'h0000_0000, "CTRL reset");
    rd_check(BAUD,   32'd433,       "BAUD reset");
    rd_check(STATUS, 32'h0000_000A, "STATUS reset");
    rd_check(TXDATA, 32'h0000_0000, "TXDATA reset");
    rd_check(RXDATA, 32'h0000_0000, "RXDATA reset");
    rd_check(IER,    32'h0000_0000, "IER reset");
    rd_check(ISR,    32'h0000_0001, "ISR reset");
    item("UART-14");
    rd_check(12'h01C, 32'h0, "reserved 0x1C");
    rd_check(12'h100, 32'h0, "reserved 0x100");
    rd_check(12'hFFC, 32'h0, "reserved 0xFFC");
    item("UART-42");
    irq_check(1'b0, "irq after reset");

    // ---------------------------------------------------------------- T2 register access
    $display("T2 register access, strobes, prohibited parity");
    item("UART-02");
    wr(CTRL, 32'hFFFF_FFF3);                          // all bits except parity
    rd_check(CTRL, 32'h33, "CTRL reserved bits read 0");
    wr(CTRL, 32'h04);  rd_check(CTRL, 32'h04, "CTRL parity even");
    wr(CTRL, 32'h08);  rd_check(CTRL, 32'h08, "CTRL parity odd");
    wr(CTRL, 32'h3F);  rd_check(CTRL, 32'h3B, "CTRL parity=11 keeps odd, other bits written");
    wr(CTRL, 32'h04);
    wr(CTRL, 32'h0C);  rd_check(CTRL, 32'h04, "CTRL parity=11 keeps even, other bits cleared");
    wr(CTRL, 32'h00);
    wr(CTRL, 32'h0F);  rd_check(CTRL, 32'h03, "CTRL parity=11 keeps none");
    apb_write(CTRL, 32'h0000_0030, 4'b1110);
    rd_check(CTRL, 32'h03, "CTRL write with pstrb[0]=0 ignored");
    apb_write(CTRL, 32'h0000_0000, 4'b0001);
    rd_check(CTRL, 32'h00, "CTRL write with pstrb[0]=1");
    item("UART-04");
    apb_write(BAUD, 32'h1234_ABCD, 4'b0001);
    rd_check(BAUD, 32'h0000_01CD, "BAUD byte 0 only");
    apb_write(BAUD, 32'h1234_56EF, 4'b0010);
    rd_check(BAUD, 32'h0000_56CD, "BAUD byte 1 only");
    apb_write(BAUD, 32'hFFFF_0000, 4'b1100);
    rd_check(BAUD, 32'h0000_56CD, "BAUD upper strobes ignored");
    wr(BAUD, 32'hFFFF_FFFF);
    rd_check(BAUD, 32'h0000_FFFF, "BAUD reserved bits read 0");
    wr(BAUD, 32'd433);
    item("UART-12");
    wr(IER, 32'hFFFF_FFFF);
    rd_check(IER, 32'h3F, "IER all bits");
    apb_write(IER, 32'h0, 4'b1110);
    rd_check(IER, 32'h3F, "IER pstrb[0]=0 ignored");
    wr(IER, 32'h0);
    rd_check(IER, 32'h0, "IER cleared");
    item("UART-06");
    wr(STATUS, 32'hFFFF_FFFF);
    rd_check(STATUS, 32'h0A, "STATUS is read-only");
    item("UART-44");
    wr(ISR, 32'hFFFF_FFFF);
    rd_check(ISR, 32'h01, "ISR level bits read-only");
    item("UART-10");
    wr(RXDATA, 32'hFF);
    rd_check(STATUS, 32'h0A, "RXDATA write ignored");
    item("UART-20");
    apb_write(TXDATA, 32'h55, 4'b1110);
    rd_check(STATUS, 32'h0A, "TXDATA write with pstrb[0]=0 does not push");
    item("UART-14");
    wr(12'h01C, 32'hFFFF_FFFF);
    wr(12'h800, 32'hFFFF_FFFF);
    rd_check(CTRL, 32'h0, "reserved writes leave CTRL");
    rd_check(BAUD, 32'd433, "reserved writes leave BAUD");
    rd_check(IER, 32'h0, "reserved writes leave IER");
    item("UART-04");
    // byte-lane aliases: paddr[1:0] are don't care
    rd_check(12'h005, 32'd433, "BAUD at paddr[1:0]=01");
    item("UART-20");
    // SETUP phase without ACCESS has no side effect
    @(posedge clk); #1;
    psel = 1'b1; penable = 1'b0; pwrite = 1'b1; paddr = TXDATA; pwdata = 32'h77; pstrb = 4'hF;
    clks(3); #1;
    psel = 1'b0; pwrite = 1'b0; pstrb = 4'h0;
    rd_check(STATUS, 32'h0A, "TXDATA in SETUP only does not push");

    // ---------------------------------------------------------------- T3 TX formats
    $display("T3 TX: baud 3..15, parity none/even/odd, 1/2 stop bits");
    item("UART-24");
    tx_case(3,  2'b00, 1'b0, 4);
    item("UART-25");
    tx_case(4,  2'b01, 1'b0, 3);
    tx_case(5,  2'b10, 1'b0, 3);
    item("UART-26");
    tx_case(7,  2'b00, 1'b1, 3);
    tx_case(9,  2'b01, 1'b1, 3);
    tx_case(12, 2'b10, 1'b1, 3);
    item("UART-24");
    tx_case(15, 2'b00, 1'b0, 3);
    item("UART-25");
    tx_case(10, 2'b01, 1'b0, 2);
    tx_fixed(6, 2'b01, 1'b0, 8'h07, 8'h03);       // even: parity bits 1, 0
    tx_fixed(6, 2'b10, 1'b0, 8'h07, 8'h03);       // odd:  parity bits 0, 1
    item("UART-24");
    tx_fixed(1000, 2'b00, 1'b0, 8'h3C, 8'hC3);

    // ---------------------------------------------------------------- T4 RX formats
    $display("T4 RX: baud 3..15, parity none/even/odd, 1/2 stop bits");
    item("UART-31");
    rx_case(3,  2'b00, 1'b0, 4);
    item("UART-32");
    rx_case(4,  2'b01, 1'b0, 3);
    rx_case(6,  2'b10, 1'b0, 3);
    item("UART-31");
    rx_case(7,  2'b00, 1'b1, 3);
    item("UART-32");
    rx_case(8,  2'b01, 1'b1, 3);
    rx_case(11, 2'b10, 1'b1, 3);
    item("UART-31");
    rx_case(15, 2'b00, 1'b0, 3);

    // ---------------------------------------------------------------- T5 busy status bits
    item("UART-30");
    $display("T5 STATUS tx_busy / rx_busy");
    div = 15;
    wr(BAUD, div);
    mon_cfg(div, 2'b00, 1'b0);
    wr(CTRL, C_TXEN | C_RXEN);
    apb_write(TXDATA, 32'hC3, 4'h1);
    clks(20);
    rd_mask(STATUS, S_TXBUSY | S_TXEMPTY, S_TXBUSY | S_TXEMPTY, "tx_busy during frame (FIFO already empty)");
    wait_tx(1, 20);
    expect_tx(8'hC3, "busy test byte");
    clks(2);
    rd_mask(STATUS, S_TXBUSY, 32'h0, "tx_busy low after frame");
    item("UART-40");
    fork
      send_ok(8'h3C, div, 2'b00, 1'b0);
      begin
        clks(40);
        rd_mask(STATUS, S_RXBUSY, S_RXBUSY, "rx_busy during frame");
      end
    join
    clks(4);
    rd_mask(STATUS, S_RXBUSY | S_RXEMPTY, 32'h0, "rx_busy low, byte in FIFO");
    rd_check(RXDATA, 32'h3C, "busy test RX byte");

    // ---------------------------------------------------------------- T6 default baud 433
    $display("T6 default baud 433 (115200 at 50 MHz)");
    item("UART-23");
    tx_fixed(433, 2'b00, 1'b0, 8'h55, 8'hA6);
    item("UART-31");
    wr(BAUD, 32'd433);
    wr(CTRL, C_RXEN);
    send_ok(8'h55, 433, 2'b00, 1'b0);
    send_ok(8'hA6, 433, 2'b00, 1'b0);
    send_ok(8'h00, 433, 2'b00, 1'b0);
    send_ok(8'hFF, 433, 2'b00, 1'b0);
    clks(4);
    rd_check(RXDATA, 32'h55, "RX 433 byte 0");
    rd_check(RXDATA, 32'hA6, "RX 433 byte 1");
    rd_check(RXDATA, 32'h00, "RX 433 byte 2");
    rd_check(RXDATA, 32'hFF, "RX 433 byte 3");
    rd_check(ISR, I_TXEMPTY, "RX 433: no error flag");
    item("UART-23");
    wr(BAUD, 32'd433);
    mon_cfg(433, 2'b00, 1'b0);
    wr(CTRL, C_TXEN | C_RXEN);
    apb_write(TXDATA, 32'h4B, 4'h1);
    send_ok(8'hD2, 433, 2'b00, 1'b0);       // runs in parallel with the TX frame
    wait_tx(1, 20);
    expect_tx(8'h4B, "TX at baud 433");
    item("UART-31");
    rd_check(RXDATA, 32'hD2, "RX at baud 433");

    // ---------------------------------------------------------------- T7 loopback
    item("UART-41");
    $display("T7 loopback");
    div = 5;
    wr(BAUD, div);
    wr(CTRL, C_TXEN | C_RXEN | C_LOOP | C_ODD | C_STOP2);
    clks(2);
    tx_idle_check = 1'b1;
    bytes.delete();
    for (int i = 0; i < 5; i++) bytes.push_back(8'(8'h11 * (i + 3)));
    foreach (bytes[i]) apb_write(TXDATA, {24'd0, bytes[i]}, 4'h1);
    // an external frame on uart_rx_i must be ignored in loopback
    send_ok(8'hEE, div, 2'b10, 1'b1);
    clks(5 * 12 * (div + 1) + 20);
    tx_idle_check = 1'b0;
    check(tx_got.size() == 0, "loopback: nothing decoded on uart_tx_o");
    foreach (bytes[i]) rd_check(RXDATA, {24'd0, bytes[i]}, $sformatf("loopback byte %0d", i));
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "loopback: FIFOs empty, engines idle");
    rd_check(ISR, I_TXEMPTY, "loopback: no error flags");
    wr(CTRL, 32'h0);

    // ---------------------------------------------------------------- T8 false start
    item("UART-36");
    $display("T8 false start rejection");
    div = 15;
    wr(BAUD, div);
    wr(CTRL, C_RXEN);
    #3;
    rx_line = 1'b0; #(CLK_NS);           rx_line = 1'b1;   // one-clock glitch
    clks(3 * (div + 1));
    rx_line = 1'b0; #(5 * CLK_NS);       rx_line = 1'b1;   // glitch shorter than half a bit
    clks(3 * (div + 1));
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "false start: nothing received, rx idle");
    rd_check(ISR, I_TXEMPTY, "false start: no flags");
    send_ok(8'h96, div, 2'b00, 1'b0);
    clks(4);
    rd_check(RXDATA, 32'h96, "frame after false starts");
    rd_mask(STATUS, S_RXEMPTY, S_RXEMPTY, "only one byte after false starts");

    // ---------------------------------------------------------------- T9 frame error
    $display("T8b mid-bit sampling with skewed edges");
    item("UART-37");
    div = 15;
    wr(BAUD, div);
    wr(CTRL, C_RXEN);
    uart_send_skew(8'hA5, div, 4);
    uart_send_skew(8'h5A, div, -4);
    uart_send_skew(8'h0F, div, 4);
    clks(4);
    rd_check(RXDATA, 32'hA5, "skewed edges +4/-4: byte A5");
    rd_check(RXDATA, 32'h5A, "skewed edges -4/+4: byte 5A");
    rd_check(RXDATA, 32'h0F, "skewed edges +4/-4: byte 0F");
    rd_check(ISR, I_TXEMPTY, "skewed edges: no error flag");
    item("UART-34");
    $display("T9 frame error");
    div = 7;
    wr(BAUD, div);
    wr(CTRL, C_RXEN);
    uart_send(8'h81, div, 2'b00, 1'b0, 1'b0, 2'b01);
    clks(4);
    rd_check(ISR, I_TXEMPTY | I_RXNE | I_FERR, "frame_err set, byte stored");
    rd_check(RXDATA, 32'h81, "byte with frame error is stored");
    item("UART-43");
    apb_write(ISR, I_FERR, 4'b1110);
    rd_check(ISR, I_TXEMPTY | I_FERR, "frame_err not cleared with pstrb[0]=0");
    apb_write(ISR, 32'h0, 4'b0001);
    rd_check(ISR, I_TXEMPTY | I_FERR, "frame_err not cleared by writing 0");
    apb_write(ISR, I_FERR, 4'b0001);
    rd_check(ISR, I_TXEMPTY, "frame_err cleared by W1C");
    item("UART-35");
    // two stop bits: the second one is checked too
    wr(CTRL, C_RXEN | C_STOP2);
    uart_send(8'h42, div, 2'b00, 1'b1, 1'b0, 2'b10);
    clks(4);
    rd_check(ISR, I_TXEMPTY | I_RXNE | I_FERR, "frame_err on second stop bit");
    rd_check(RXDATA, 32'h42, "byte with bad stop bit 2");
    wr(ISR, I_FERR);
    send_ok(8'h24, div, 2'b00, 1'b1);
    clks(4);
    rd_check(ISR, I_TXEMPTY | I_RXNE, "good 2-stop frame: no frame_err");
    rd_check(RXDATA, 32'h24, "good 2-stop byte");

    // ---------------------------------------------------------------- T10 parity error
    item("UART-33");
    $display("T10 parity error (even and odd)");
    wr(CTRL, C_RXEN | C_EVEN);
    uart_send(8'h37, div, 2'b01, 1'b0, 1'b1, 2'b00);
    clks(4);
    rd_check(ISR, I_TXEMPTY | I_RXNE | I_PERR, "parity_err even");
    rd_check(RXDATA, 32'h37, "byte with even parity error stored");
    item("UART-43");
    apb_write(ISR, 32'hFFFF_FFFF, 4'b1110);
    rd_check(ISR, I_TXEMPTY | I_PERR, "parity_err not cleared with pstrb[0]=0");
    wr(ISR, I_PERR);
    rd_check(ISR, I_TXEMPTY, "parity_err cleared");
    item("UART-32");
    wr(CTRL, C_RXEN | C_ODD);
    send_ok(8'h37, div, 2'b10, 1'b0);
    clks(4);
    rd_check(ISR, I_TXEMPTY | I_RXNE, "odd parity ok");
    rd_check(RXDATA, 32'h37, "odd parity byte");
    item("UART-33");
    uart_send(8'hF0, div, 2'b10, 1'b0, 1'b1, 2'b00);
    clks(4);
    rd_check(ISR, I_TXEMPTY | I_RXNE | I_PERR, "parity_err odd");
    rd_check(RXDATA, 32'hF0, "byte with odd parity error stored");
    // even-parity frame while receiver expects odd -> error
    uart_send(8'h01, div, 2'b01, 1'b0, 1'b0, 2'b00);
    clks(4);
    rd_check(RXDATA, 32'h01, "even frame into odd receiver");
    rd_mask(ISR, I_PERR, I_PERR, "parity_err still set");
    wr(ISR, 32'h3F);
    rd_check(ISR, I_TXEMPTY, "all flags cleared");

    // ---------------------------------------------------------------- T11 RX FIFO full / overrun / empty read
    $display("T11 RX FIFO full, overrun, read when empty");
    wr(CTRL, C_RXEN);
    div = 3;
    wr(BAUD, div);
    item("UART-22");
    rd_check(RXDATA, 32'h0, "RXDATA read when empty returns 0");
    rd_check(RXDATA, 32'h0, "RXDATA read when empty returns 0 (again)");
    item("UART-38");
    bytes.delete();
    for (int i = 0; i < 16; i++) bytes.push_back(8'(i * 13 + 7));
    foreach (bytes[i]) send_ok(bytes[i], div, 2'b00, 1'b0);
    clks(4);
    rd_check(STATUS, S_TXEMPTY | S_RXFULL, "RX FIFO full");
    rd_check(ISR, I_TXEMPTY | I_RXNE, "no overrun yet");
    send_ok(8'hBD, div, 2'b00, 1'b0);
    clks(4);
    rd_check(ISR, I_TXEMPTY | I_RXNE | I_OVR, "overrun set");
    rd_check(STATUS, S_TXEMPTY | S_RXFULL, "RX FIFO still full");
    foreach (bytes[i]) rd_check(RXDATA, {24'd0, bytes[i]}, $sformatf("RX FIFO entry %0d", i));
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "RX FIFO empty, lost byte not stored");
    rd_check(RXDATA, 32'h0, "lost byte not in FIFO");
    rd_check(ISR, I_TXEMPTY | I_OVR, "overrun stays until cleared");
    wr(ISR, I_OVR);
    rd_check(ISR, I_TXEMPTY, "overrun cleared");
    item("UART-21");
    // RXDATA read in SETUP phase only does not pop
    send_ok(8'h6E, div, 2'b00, 1'b0);
    clks(4);
    @(posedge clk); #1;
    psel = 1'b1; penable = 1'b0; pwrite = 1'b0; paddr = RXDATA;
    clks(3); #1;
    psel = 1'b0;
    rd_check(RXDATA, 32'h6E, "RXDATA not popped by SETUP phase");
    rd_mask(STATUS, S_RXEMPTY, S_RXEMPTY, "RX empty after one pop");

    // ---------------------------------------------------------------- T12 rx_en = 0
    item("UART-39");
    $display("T12 rx_en = 0 ignores frames");
    wr(CTRL, 32'h0);
    fork
      send_ok(8'h99, div, 2'b00, 1'b0);
      begin
        clks(8);
        rd_mask(STATUS, S_RXBUSY, 32'h0, "rx_busy stays 0 when rx disabled");
      end
    join
    clks(4);
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "rx disabled: nothing stored");
    rd_check(ISR, I_TXEMPTY, "rx disabled: no flags");

    // ---------------------------------------------------------------- T13 TX FIFO full / tx_ovf / tx_en
    item("UART-27");
    $display("T13 TX FIFO full, tx_ovf, tx_en");
    div = 4;
    wr(BAUD, div);
    mon_cfg(div, 2'b00, 1'b0);
    wr(CTRL, 32'h0);
    tx_idle_check = 1'b1;
    bytes.delete();
    for (int i = 0; i < 16; i++) bytes.push_back(8'(240 - i * 7));
    foreach (bytes[i]) begin
      apb_write(TXDATA, {24'd0, bytes[i]}, 4'h1);
      if (i == 0) rd_check(STATUS, S_RXEMPTY, "TX FIFO not empty after one write");
    end
    rd_check(STATUS, S_RXEMPTY | S_TXFULL, "TX FIFO full");
    rd_check(ISR, 32'h0, "tx_empty level low, no tx_ovf yet");
    item("UART-20");
    apb_write(TXDATA, 32'h00, 4'b1110);
    rd_check(ISR, 32'h0, "no tx_ovf for write with pstrb[0]=0");
    item("UART-28");
    apb_write(TXDATA, 32'h5D, 4'b0001);
    rd_check(ISR, I_TXOVF, "tx_ovf set");
    item("UART-29");
    clks(40);
    tx_idle_check = 1'b0;
    check(tx_got.size() == 0, "tx_en=0: nothing sent");
    rd_check(STATUS, S_RXEMPTY | S_TXFULL, "tx_en=0: TX FIFO keeps its data");
    item("UART-27");
    wr(CTRL, C_TXEN);
    wait_tx(16, 16 * 10 + 20);
    foreach (bytes[i]) expect_tx(bytes[i], $sformatf("TX FIFO entry %0d", i));
    item("UART-28");
    clks(4 * (div + 1) * 10);
    check(tx_got.size() == 0, "dropped byte is not sent");
    rd_check(ISR, I_TXEMPTY | I_TXOVF, "tx_ovf stays, tx_empty back");
    item("UART-43");
    apb_write(ISR, I_TXOVF, 4'b1110);
    rd_check(ISR, I_TXEMPTY | I_TXOVF, "tx_ovf not cleared with pstrb[0]=0");
    wr(ISR, I_TXOVF | I_TXEMPTY | I_RXNE);
    rd_check(ISR, I_TXEMPTY, "tx_ovf cleared");
    item("UART-29");
    // tx_en cleared during a frame: the frame completes, the next one waits
    div = 15;
    wr(BAUD, div);
    mon_cfg(div, 2'b01, 1'b0);
    wr(CTRL, C_EVEN);
    apb_write(TXDATA, 32'hA1, 4'h1);
    apb_write(TXDATA, 32'hB2, 4'h1);
    wr(CTRL, C_TXEN | C_EVEN);
    clks(30);
    wr(CTRL, C_EVEN);
    rd_mask(STATUS, S_TXBUSY | S_TXEMPTY, S_TXBUSY, "tx_en=0 mid-frame: still busy, byte 2 waits");
    clks(3 * 11 * (div + 1));
    check(tx_got.size() == 1, $sformatf("tx_en=0 mid-frame: %0d frames sent, expected 1", tx_got.size()));
    expect_tx(8'hA1, "frame in progress completes");
    rd_mask(STATUS, S_TXBUSY | S_TXEMPTY, 32'h0, "byte 2 kept in TX FIFO");
    wr(CTRL, C_TXEN | C_EVEN);
    wait_tx(1, 20);
    expect_tx(8'hB2, "byte 2 sent after tx_en=1");
    wr(CTRL, 32'h0);

    // ---------------------------------------------------------------- T14 IER gating
    item("UART-42");
    $display("T14 IER gating of irq_uart_o");
    // tx_empty level (ISR=0x01 now)
    irq_check(1'b0, "IER=0");
    wr(IER, 32'h3E);  irq_check(1'b0, "tx_empty set but tx_empty_ie=0");
    wr(IER, I_TXEMPTY); irq_check(1'b1, "tx_empty & tx_empty_ie");
    apb_write(TXDATA, 32'h12, 4'h1);  // tx_en=0: FIFO not empty
    irq_check(1'b0, "tx_empty low");
    wr(IER, 32'h0);
    // rx_ne level
    div = 3;
    wr(BAUD, div);
    wr(CTRL, C_RXEN | C_EVEN);
    send_ok(8'h77, div, 2'b01, 1'b0);
    clks(4);
    irq_check(1'b0, "rx_ne with IER=0");
    wr(IER, 32'h3D);  irq_check(1'b0, "rx_ne set, only other enables");
    wr(IER, I_RXNE);  irq_check(1'b1, "rx_ne & rx_ne_ie");
    item("UART-44");
    rd_check(RXDATA, 32'h77, "pop clears rx_ne");
    irq_check(1'b0, "rx_ne low after pop");
    item("UART-42");
    // parity_err
    wr(IER, 32'h3B);
    uart_send(8'h70, div, 2'b01, 1'b0, 1'b1, 2'b00);
    clks(4);
    rd_check(RXDATA, 32'h70, "parity error byte (irq test)");
    rd_check(ISR, I_PERR, "only parity_err set (tx FIFO not empty)");
    irq_check(1'b0, "parity_err with parity_err_ie=0");
    wr(IER, I_PERR);  irq_check(1'b1, "parity_err & parity_err_ie");
    wr(ISR, I_PERR);  irq_check(1'b0, "parity_err cleared");
    // frame_err
    wr(IER, 32'h37);
    uart_send(8'h0F, div, 2'b01, 1'b0, 1'b0, 2'b01);
    clks(4);
    rd_check(RXDATA, 32'h0F, "frame error byte (irq test)");
    rd_check(ISR, I_FERR, "only frame_err set");
    irq_check(1'b0, "frame_err with frame_err_ie=0");
    wr(IER, I_FERR);  irq_check(1'b1, "frame_err & frame_err_ie");
    wr(ISR, I_FERR);  irq_check(1'b0, "frame_err cleared");
    // overrun
    wr(IER, 32'h2D);
    for (int i = 0; i < 17; i++) send_ok(8'(i), div, 2'b01, 1'b0);
    clks(4);
    rd_check(ISR, I_RXNE | I_OVR, "overrun (irq test)");
    irq_check(1'b0, "overrun with overrun_ie=0 (rx_ne_ie=0)");
    wr(IER, I_OVR);   irq_check(1'b1, "overrun & overrun_ie");
    for (int i = 0; i < 16; i++) rd_check(RXDATA, 32'(i), "drain RX FIFO");
    irq_check(1'b1, "overrun irq stays after drain");
    wr(ISR, I_OVR);   irq_check(1'b0, "overrun cleared");
    // tx_ovf
    wr(IER, 32'h1F);
    for (int i = 0; i < 16; i++) apb_write(TXDATA, 32'(i), 4'h1);  // 1 already inside
    rd_check(ISR, I_TXOVF, "tx_ovf (irq test)");
    irq_check(1'b0, "tx_ovf with tx_ovf_ie=0");
    wr(IER, I_TXOVF); irq_check(1'b1, "tx_ovf & tx_ovf_ie");
    wr(ISR, I_TXOVF); irq_check(1'b0, "tx_ovf cleared");
    // drain the TX FIFO so the TB ends idle
    mon_cfg(div, 2'b01, 1'b0);
    wr(CTRL, C_TXEN | C_EVEN);
    wait_tx(16, 16 * 11 + 20);
    expect_tx(8'h12, "tx drain 0");
    for (int i = 0; i < 15; i++) expect_tx(8'(i), "tx drain");
    clks(20);
    rd_check(STATUS, S_TXEMPTY | S_RXEMPTY, "final STATUS");
    wr(IER, I_TXEMPTY);
    irq_check(1'b1, "final tx_empty irq");

    vplan_pkg::report(VP_BLOCK, VP_N);
    $finish;
  end

  initial begin
    #20_000_000;
    $display("ERROR: timeout");
    $display("TEST FAILED: timeout");
    $finish;
  end

endmodule
