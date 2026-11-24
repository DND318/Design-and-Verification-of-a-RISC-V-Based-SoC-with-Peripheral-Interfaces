// Driver: takes packets from the stimulus (s2d_mb) and drives the APB pins
// through the virtual interface. Inputs change 1 ns after a rising edge;
// PRDATA / PREADY / PSLVERR are sampled at the falling edge of ACCESS.
// The finished packet goes back to the stimulus on d2s_mb.
class apb_driver;
  virtual apb_if        vif;
  mailbox #(apb_packet) s2d_mb;
  mailbox #(apb_packet) d2s_mb;
  bit                   verbose;

  function new(virtual apb_if vif, mailbox #(apb_packet) s2d_mb, mailbox #(apb_packet) d2s_mb);
    this.vif    = vif;
    this.s2d_mb = s2d_mb;
    this.d2s_mb = d2s_mb;
    verbose = $test$plusargs("VERBOSE");
  endfunction

  task run();
    apb_packet p;
    bit        in_b2b = 1'b0;
    vif.psel = 1'b0; vif.penable = 1'b0; vif.pwrite = 1'b0;
    vif.paddr = 12'h0; vif.pwdata = 32'h0; vif.pstrb = 4'h0;
    forever begin
      s2d_mb.get(p);
      if (verbose) $display("%0t: [driver] Get packet from stimulus: %s", $time, p.sprint());
      case (p.kind)
        APB_IDLE: begin
          repeat (p.n_idle) @(posedge vif.clk);
          #1;
        end
        APB_SETUP_ONLY: begin
          @(posedge vif.clk); #1;
          vif.psel = 1'b1; vif.penable = 1'b0; vif.pwrite = p.write;
          vif.paddr = p.addr; vif.pwdata = p.data; vif.pstrb = p.strb;
          @(posedge vif.clk); #1;
          vif.psel = 1'b0; vif.pwrite = 1'b0; vif.pstrb = 4'h0;
        end
        default: begin
          drive_xfer(p, in_b2b);
          // keep PSEL High if the next packet is a back-to-back transfer
          in_b2b = 1'b0;
          if (s2d_mb.num() > 0) begin
            apb_packet nxt;
            void'(s2d_mb.try_peek(nxt));
            in_b2b = (nxt.kind == APB_XFER) && nxt.b2b;
          end
          if (!in_b2b) begin
            vif.psel = 1'b0; vif.penable = 1'b0;
            if (p.pre_post) begin
              vif.pwdata = p.post_data;            // data changes after the transfer
              @(posedge vif.clk); #1;
            end
            vif.pwrite = 1'b0; vif.pstrb = 4'h0;
          end
        end
      endcase
      d2s_mb.put(p);
    end
  endtask

  // SETUP, ACCESS (wait for PREADY), end 1 ns after the ACCESS edge with PSEL still High
  task drive_xfer(apb_packet p, bit b2b);
    int unsigned w = 0;
    if (!b2b) begin
      repeat (p.gap) @(posedge vif.clk);
      if (p.pre_post) begin
        @(posedge vif.clk); #1;
        vif.psel = 1'b0; vif.pwrite = 1'b1; vif.paddr = p.addr; vif.pwdata = p.pre_data;
        vif.pstrb = 4'hF;
      end
      @(posedge vif.clk); #1;
    end
    vif.psel = 1'b1; vif.penable = 1'b0; vif.pwrite = p.write; vif.paddr = p.addr;
    vif.pstrb = p.write ? p.strb : 4'h0;
    if (p.write) vif.pwdata = p.data;
    @(posedge vif.clk); #1;
    vif.penable = 1'b1;
    @(negedge vif.clk);
    while (vif.pready !== 1'b1 && w < 64) begin
      @(negedge vif.clk);
      w++;
    end
    p.rdata      = vif.prdata;
    p.pready     = vif.pready;
    p.pslverr    = vif.pslverr;
    p.cyc_sample = vif.cyc;
    @(posedge vif.clk); #1;
    p.cyc_end    = vif.cyc;
    vif.penable  = 1'b0;
  endtask
endclass
