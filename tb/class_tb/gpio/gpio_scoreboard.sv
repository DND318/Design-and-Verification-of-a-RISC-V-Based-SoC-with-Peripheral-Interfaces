// GPIO scoreboard (reference model)
class gpio_scoreboard;
  mailbox #(apb_packet)  apb_m2s_mb;
  mailbox #(gpio_packet) gpio_m2s_mb;

  // reference model (state after the last stepped edge)
  bit [7:0]        out_r, oe_r, ie_r, is_r;
  bit [7:0]        sync1, sync2, prev;  // synchronizer stages, last synchronized value
  bit [7:0]        pin_next;            // gpio_i that the DUT samples at the next edge
  longint unsigned m_edge;

  int unsigned     n_xfer, n_rd, n_edges, n_set, n_err;
  bit              verbose;
  bit              en_fc = 1'b1;
  `include "coverage.sv"

  function new(mailbox #(apb_packet) apb_m2s_mb, mailbox #(gpio_packet) gpio_m2s_mb);
    this.apb_m2s_mb  = apb_m2s_mb;
    this.gpio_m2s_mb = gpio_m2s_mb;
    verbose = $test$plusargs("VERBOSE");
    reset();
`ifndef VERILATOR
    APB_GROUP = new();   // embedded covergroups are created in the constructor
    PIN_GROUP = new();
    IRQ_GROUP = new();
`endif
  endfunction

  function void reset();
    {out_r, oe_r, ie_r, is_r, sync1, sync2, prev} = '0;
  endfunction

  function void check(bit ok, string what);
    if (!ok) n_err++;
    vplan_pkg::chk(ok, what);
  endfunction

  function bit [31:0] read(bit [11:0] addr);
    case (addr[11:2])
      10'd0:   return {24'd0, out_r};
      10'd1:   return {24'd0, oe_r};
      10'd2:   return {24'd0, sync2};
      10'd3:   return {24'd0, ie_r};
      10'd4:   return {24'd0, is_r};
      default: return 32'd0;
    endcase
  endfunction

  // One rising edge
  function void step(bit wr, bit [11:0] addr, bit [31:0] data, bit [3:0] strb, bit [7:0] pin);
    bit [7:0] rise = sync2 & ~prev;
    bit [7:0] is_d = is_r;
    if (wr && strb[0] && addr[11:2] == 10'd4) is_d = is_d & ~data[7:0];   // W1C first
    is_d = is_d | (rise & ie_r);                                           // then set (set wins)
    if (rise & ie_r) n_set++;
    if (en_fc) sample_pin_fc(rise, ie_r);
    prev  = sync2;
    sync2 = sync1;
    sync1 = pin;
    is_r  = is_d;
    if (wr && strb[0]) begin
      case (addr[11:2])
        10'd0: out_r = data[7:0];
        10'd1: oe_r  = data[7:0];
        10'd3: ie_r  = data[7:0];
        default: ;
      endcase
    end
  endfunction

  task run();
    gpio_packet g;
    apb_packet  a;
    bit         have_a;
    while (1) begin
      gpio_m2s_mb.get(g);
      n_edges++;
      // APB packet of this edge, if any (put at the rising edge, before this falling edge)
      have_a = 1'b0;
      while (apb_m2s_mb.try_peek(a) && a.edge_no <= g.edge_no) begin
        void'(apb_m2s_mb.try_get(a));
        if (a.edge_no == g.edge_no) have_a = 1'b1;
      end
      if (!g.rst_n) begin
        reset();
        pin_next = g.gpio_i;
        continue;
      end
      if (have_a && a.xfer && a.rst_n) begin
        n_xfer++;
        if (en_fc) sample_apb_fc(a);
        check(a.pready && !a.pslverr, $sformatf("[scoreboard] %s: PREADY=%b PSLVERR=%b", a.sprint(), a.pready, a.pslverr));
        if (!a.write) begin
          n_rd++;
          check(a.rdata === read(a.addr), $sformatf("[scoreboard] read %h = %h, model expects %h",
                                                    a.addr, a.rdata, read(a.addr)));
        end
        if (verbose) $display("%0t: [scoreboard] Get packet from monitor: %s", $time, a.sprint());
      end
      step(have_a && a.xfer && a.rst_n && a.write, a == null ? 12'h0 : a.addr,
           a == null ? 32'h0 : a.data, a == null ? 4'h0 : a.strb, pin_next);
      pin_next = g.gpio_i;
      m_edge   = g.edge_no;
      check(g.gpio_o === out_r && g.gpio_oe === oe_r,
            $sformatf("[scoreboard] edge %0d: gpio_o=%h gpio_oe=%h, model expects %h %h",
                      g.edge_no, g.gpio_o, g.gpio_oe, out_r, oe_r));
      check(g.irq === |(is_r & ie_r),
            $sformatf("[scoreboard] edge %0d: irq_gpio_o=%b, model expects %b (IS %h, IE %h)",
                      g.edge_no, g.irq, |(is_r & ie_r), is_r, ie_r));
      if (en_fc) sample_irq_fc(is_r, ie_r, g.irq);
    end
  endtask

  function void report();
    $display("%0t: [scoreboard] %0d transfers, %0d reads compared, %0d clocks compared, %0d IS bits set, %0d mismatches",
             $time, n_xfer, n_rd, n_edges, n_set, n_err);
    report_fc();
  endfunction
endclass
