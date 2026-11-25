// Bus functional coverage (included in the scoreboard)
`ifndef VERILATOR
  bus_packet ax_trans, apb_trans, m2_trans;
  int        cv_tgt;

  covergroup AXI_GROUP;
    axi_dir: coverpoint ax_trans.we { bins read = {0}; bins write = {1}; }
    axi_target: coverpoint cv_tgt { bins sram = {0}; bins apb = {1}; bins apb_disabled = {2}; bins unmapped = {3}; }
    axi_resp: coverpoint ax_trans.resp { bins okay = {0}; bins slverr = {2}; bins decerr = {3}; }
    axi_prot: coverpoint ax_trans.prot { bins data = {3'b001}; bins instr = {3'b101}; }
    axi_strb: coverpoint ax_trans.wstrb iff (ax_trans.we) {
      bins full = {4'hF}; bins one_byte[] = {4'h1, 4'h2, 4'h4, 4'h8}; bins half[] = {4'h3, 4'hC}; bins other = default;
    }
    axi_source: coverpoint ax_trans.direct { bins master = {0}; bins direct = {1}; }
    dir_target: cross axi_dir, axi_target;
  endgroup

  covergroup APB_GROUP;
    apb_dir: coverpoint apb_trans.we { bins read = {0}; bins write = {1}; }
    apb_slot: coverpoint apb_trans.slot { bins slot[] = {[0:5]}; }
    apb_waits: coverpoint apb_trans.waits { bins none = {0}; bins one = {1}; bins two = {2}; bins more = {[3:$]}; }
    apb_err: coverpoint apb_trans.pslverr { bins okay = {0}; bins slverr = {1}; }
    dir_slot: cross apb_dir, apb_slot;
    dir_err: cross apb_dir, apb_err;
  endgroup

  covergroup M2_GROUP;
    m2_dir: coverpoint m2_trans.we { bins read = {0}; bins write = {1}; }
    m2_resp: coverpoint m2_trans.resp { bins okay = {0}; bins exokay = {1}; bins slverr = {2}; bins decerr = {3}; }
    m2_prot: coverpoint m2_trans.prot { bins data = {3'b001}; bins instr = {3'b101}; }
    dir_resp: cross m2_dir, m2_resp;
  endgroup

  function void sample_axi_fc(bus_packet pkt, int tgt);
    ax_trans = pkt;
    cv_tgt   = tgt;
    AXI_GROUP.sample();
  endfunction

  function void sample_apb_fc(bus_packet pkt);
    apb_trans = pkt;
    APB_GROUP.sample();
  endfunction

  function void sample_m2_fc(bus_packet pkt);
    m2_trans = pkt;
    M2_GROUP.sample();
  endfunction

  function void report_fc();
    $display("%0t: [scoreboard] coverage: xbar %0.1f%%, apb %0.1f%%, master 2 %0.1f%%", $time,
             AXI_GROUP.get_coverage(), APB_GROUP.get_coverage(), M2_GROUP.get_coverage());
  endfunction
`else
  function void sample_axi_fc(bus_packet pkt, int tgt); endfunction
  function void sample_apb_fc(bus_packet pkt);          endfunction
  function void sample_m2_fc(bus_packet pkt);           endfunction
  function void report_fc();                            endfunction
`endif
