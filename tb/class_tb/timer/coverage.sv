// Timer functional coverage (included in the scoreboard)
`ifndef VERILATOR
  // sampled values for the covergroups
  bit [11:0] cv_addr;
  bit        cv_write;
  bit [3:0]  cv_strb;
  bit [3:0]  cv_div_val;
  bit        cv_div_en, cv_timer_en, cv_cmp_ie, cv_match;
  bit [31:0] cv_wdata;

  covergroup APB_GROUP;
    cp_addr: coverpoint cv_addr {
      bins tcr   = {12'h000};
      bins tier  = {12'h004};
      bins tisr  = {12'h008};
      bins tdr0  = {12'h010};
      bins tdr1  = {12'h014};
      bins tcmp0 = {12'h018};
      bins tcmp1 = {12'h01C};
      bins rsvd  = {12'h00C, [12'h020:12'hFFC]};
    }
    cp_dir:  coverpoint cv_write { bins rd = {0}; bins wr = {1}; }
    cp_strb: coverpoint cv_strb  { bins none = {4'h0}; bins full = {4'hF};
                                   bins one[] = {4'h1, 4'h2, 4'h4, 4'h8};
                                   bins other = {[4'h3:4'hE]}; }
    x_addr_dir: cross cp_addr, cp_dir;
  endgroup

  covergroup CFG_GROUP;
    cp_div_val: coverpoint cv_div_val { bins v[] = {[0:8]}; }
    cp_div_en:  coverpoint cv_div_en;
    cp_tcr_wr:  coverpoint cv_wdata[11:8] { bins legal = {[0:8]}; bins prohibited = {[9:15]}; }
    x_rate: cross cp_div_val, cp_div_en;
  endgroup

  covergroup IRQ_GROUP;
    cp_timer_en: coverpoint cv_timer_en;
    cp_cmp_ie:   coverpoint cv_cmp_ie;
    cp_match:    coverpoint cv_match;
    cp_irq:      coverpoint obs_irq { bins rise = (0 => 1); bins fall = (1 => 0); }
    x_gate: cross cp_cmp_ie, cp_match;
  endgroup

  function void sample_apb_fc(apb_packet p);
    cv_addr = p.addr; cv_write = p.write; cv_strb = p.strb; cv_wdata = p.data;
    APB_GROUP.sample();
    if (p.write && p.addr[11:2] == 10'h000) CFG_GROUP.sample();
  endfunction

  function void sample_irq_fc(timer_model m);
    cv_div_val = m.div_val; cv_div_en = m.div_en; cv_timer_en = m.timer_en;
    cv_cmp_ie = m.cmp_ie; cv_match = m.match();
    IRQ_GROUP.sample();
  endfunction


  function void report_fc();
    $display("%0t: [scoreboard] coverage: apb %0.1f%%, cfg %0.1f%%, irq %0.1f%%", $time,
             APB_GROUP.get_coverage(), CFG_GROUP.get_coverage(), IRQ_GROUP.get_coverage());
  endfunction
`else
  function void sample_apb_fc(apb_packet p);  endfunction
  function void sample_irq_fc(timer_model m); endfunction
  function void report_fc();                  endfunction
`endif
