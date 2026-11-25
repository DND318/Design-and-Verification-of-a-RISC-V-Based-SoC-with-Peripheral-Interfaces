// Stimulus: turns the test's requests into packets for the driver
// (s2d_mb) and waits until the driver has finished each one (d2s_mb).
// The last write and read packets are kept for tests that need their
// time stamps or read data.
class apb_stimulus;
  mailbox #(apb_packet) s2d_mb;
  mailbox #(apb_packet) d2s_mb;
  apb_packet            last_wr;
  apb_packet            last_rd;
  bit                   verbose;

  function new(mailbox #(apb_packet) s2d_mb, mailbox #(apb_packet) d2s_mb);
    this.s2d_mb = s2d_mb;
    this.d2s_mb = d2s_mb;
    verbose = $test$plusargs("VERBOSE");
  endfunction

  // Send one packet and wait for it to complete
  task send(apb_packet p);
    apb_packet r;
    if (verbose) $display("%0t: [stimulus] Sent packet to driver: %s", $time, p.sprint());
    s2d_mb.put(p);
    d2s_mb.get(r);
    if (r.kind == APB_XFER) begin
      if (r.write) last_wr = r;
      else         last_rd = r;
    end
  endtask

  task write(input bit [11:0] a, input bit [31:0] d, input bit [3:0] s = 4'hF);
    apb_packet p = new();
    p.write = 1'b1; p.addr = a; p.data = d; p.strb = s;
    send(p);
  endtask

  task read(input bit [11:0] a, output bit [31:0] d);
    apb_packet p = new();
    p.write = 1'b0; p.addr = a; p.strb = 4'h0;
    send(p);
    d = p.rdata;
  endtask

  task idle(input int unsigned n);
    apb_packet p = new();
    p.kind = APB_IDLE; p.n_idle = n;
    send(p);
  endtask

  // SETUP phase only, then PSEL drops (no ACCESS)
  task setup_only(input bit [11:0] a, input bit w, input bit [31:0] d);
    apb_packet p = new();
    p.kind = APB_SETUP_ONLY; p.write = w; p.addr = a; p.data = d; p.strb = 4'hF;
    send(p);
  endtask

  // Write with other PWDATA values one clock before SETUP and one clock after ACCESS
  task write_pre_post(input bit [11:0] a, input bit [31:0] d0, input bit [31:0] d1,
                      input bit [31:0] d2);
    apb_packet p = new();
    p.write = 1'b1; p.addr = a; p.data = d1; p.strb = 4'hF;
    p.pre_post = 1'b1; p.pre_data = d0; p.post_data = d2;
    send(p);
  endtask

  // Two transfers with no idle clock between them (ACCESS then next SETUP)
  task pair(apb_packet p1, apb_packet p2);
    apb_packet r;
    p2.b2b = 1'b1;
    if (verbose) $display("%0t: [stimulus] Sent back-to-back pair to driver", $time);
    s2d_mb.put(p1);
    s2d_mb.put(p2);
    d2s_mb.get(r);
    d2s_mb.get(r);
  endtask

  task write_b2b(input bit [11:0] a, input bit [31:0] d1, input bit [11:0] b, input bit [31:0] d2);
    apb_packet p1 = new();
    apb_packet p2 = new();
    p1.write = 1'b1; p1.addr = a; p1.data = d1; p1.strb = 4'hF;
    p2.write = 1'b1; p2.addr = b; p2.data = d2; p2.strb = 4'hF;
    pair(p1, p2);
  endtask

  task read_b2b(input bit [11:0] a, input bit [11:0] b, output bit [31:0] d1, output bit [31:0] d2);
    apb_packet p1 = new();
    apb_packet p2 = new();
    p1.write = 1'b0; p1.addr = a; p1.strb = 4'h0;
    p2.write = 1'b0; p2.addr = b; p2.strb = 4'h0;
    pair(p1, p2);
    d1 = p1.rdata;
    d2 = p2.rdata;
  endtask
endclass
