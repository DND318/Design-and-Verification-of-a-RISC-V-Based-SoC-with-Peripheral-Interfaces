// APB monitor on the bridge output
class apb_bus_monitor;
  virtual apbm_if       dut_vif;
  mailbox #(bus_packet) m2s_mb;

  function new(virtual apbm_if dut_vif, mailbox #(bus_packet) m2s_mb);
    this.dut_vif = dut_vif;
    this.m2s_mb  = m2s_mb;
  endfunction

  task run();
    bus_packet   p;
    bit          ph;
    bit [15:0]   c_sel;
    int          s;
    while (1) begin
      @(negedge dut_vif.clk);
      if (dut_vif.rst_n !== 1'b1) begin
        ph = 0;
        continue;
      end
      if (dut_vif.psel != 16'd0) begin
        vplan_pkg::chk_at("BUS-04", $onehot(dut_vif.psel), $sformatf("[apb_monitor] more than one PSEL: %b", dut_vif.psel));
        vplan_pkg::chk_at("BUS-05", dut_vif.psel[15:6] == 10'd0,
                          $sformatf("[apb_monitor] PSEL of a disabled slot: %b", dut_vif.psel));
        if (!ph) begin                            // SETUP
          vplan_pkg::chk_at("BUS-09", dut_vif.penable === 1'b0, "[apb_monitor] first PSEL cycle is not SETUP (PENABLE = 1)");
          p = new();
          p.kind  = BUS_APB;
          c_sel   = dut_vif.psel;
          p.slot  = apb_slave::slot_of(dut_vif.psel);
          p.we    = dut_vif.pwrite;
          p.addr  = {20'd0, dut_vif.paddr};
          p.wdata = dut_vif.pwdata;
          p.wstrb = dut_vif.pstrb;
          p.prot  = dut_vif.pprot;
          p.waits = 0;
          ph = 1;
        end else begin                            // ACCESS
          vplan_pkg::chk_at("BUS-09", dut_vif.penable === 1'b1, "[apb_monitor] PENABLE not 1 after SETUP");
          vplan_pkg::chk_at("BUS-09", dut_vif.psel == c_sel && dut_vif.paddr == p.addr[11:0] &&
                                      dut_vif.pwrite == p.we && dut_vif.pwdata == p.wdata &&
                                      dut_vif.pstrb == p.wstrb && dut_vif.pprot == p.prot,
                            "[apb_monitor] PSEL / PADDR / PWRITE / PWDATA / PSTRB / PPROT changed during the transfer");
          s = p.slot;
          if (s >= 0 && dut_vif.pready[s] === 1'b1) begin
            p.rdata   = dut_vif.prdata[32*s +: 32];
            p.pslverr = dut_vif.pslverr[s];
            if ($test$plusargs("VERBOSE")) $display("%0t: [apb_monitor] %s", $time, p.sprint());
            m2s_mb.put(p);
            ph = 0;
          end else begin
            p.waits++;
          end
        end
      end else begin
        vplan_pkg::chk_at("BUS-11", !ph, "[apb_monitor] PSEL dropped before PREADY");
        ph = 0;
      end
    end
  endtask
endclass
