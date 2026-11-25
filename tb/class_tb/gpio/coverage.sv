// GPIO functional coverage (included in the scoreboard)
`ifndef VERILATOR
  apb_packet apb_trans;
  bit [7:0]  cv_rise, cv_ie, cv_is;
  bit        cv_irq;

  covergroup APB_GROUP;
    apb_transfer: coverpoint apb_trans.write { bins apb_read = {0}; bins apb_write = {1}; }
    apb_address: coverpoint apb_trans.addr[11:2] {
      bins OUT_addr  = {0};
      bins OE_addr   = {1};
      bins IN_addr   = {2};
      bins IE_addr   = {3};
      bins IS_addr   = {4};
      bins RSVD_addr = {[5:1023]};
    }
    apb_strobe: coverpoint apb_trans.strb { bins full = {4'hF}; bins byte0 = {4'h1};
                                            bins no_byte0 = {4'h0, 4'h2, 4'h4, 4'h6, 4'h8, 4'hA, 4'hC, 4'hE}; }
    apb_transaction: cross apb_transfer, apb_address;
  endgroup

  // a rising edge on each pin, with its IE bit 0 or 1
  covergroup PIN_GROUP;
    pin0: coverpoint {cv_rise[0], cv_ie[0]} { bins rise_ie0 = {2'b10}; bins rise_ie1 = {2'b11}; }
    pin1: coverpoint {cv_rise[1], cv_ie[1]} { bins rise_ie0 = {2'b10}; bins rise_ie1 = {2'b11}; }
    pin2: coverpoint {cv_rise[2], cv_ie[2]} { bins rise_ie0 = {2'b10}; bins rise_ie1 = {2'b11}; }
    pin3: coverpoint {cv_rise[3], cv_ie[3]} { bins rise_ie0 = {2'b10}; bins rise_ie1 = {2'b11}; }
    pin4: coverpoint {cv_rise[4], cv_ie[4]} { bins rise_ie0 = {2'b10}; bins rise_ie1 = {2'b11}; }
    pin5: coverpoint {cv_rise[5], cv_ie[5]} { bins rise_ie0 = {2'b10}; bins rise_ie1 = {2'b11}; }
    pin6: coverpoint {cv_rise[6], cv_ie[6]} { bins rise_ie0 = {2'b10}; bins rise_ie1 = {2'b11}; }
    pin7: coverpoint {cv_rise[7], cv_ie[7]} { bins rise_ie0 = {2'b10}; bins rise_ie1 = {2'b11}; }
  endgroup

  covergroup IRQ_GROUP;
    irq_pin: coverpoint cv_irq { bins low = {0}; bins high = {1}; bins rise = (0 => 1); bins fall = (1 => 0); }
    is_masked: coverpoint ((cv_is != 0) && ((cv_is & cv_ie) == 0)) { bins masked = {1}; }
  endgroup

  function void sample_apb_fc(apb_packet pkt);
    apb_trans = pkt;
    APB_GROUP.sample();
  endfunction

  function void sample_pin_fc(bit [7:0] rise, bit [7:0] ie);
    if (rise == 0) return;
    cv_rise = rise;
    cv_ie   = ie;
    PIN_GROUP.sample();
  endfunction

  function void sample_irq_fc(bit [7:0] is_v, bit [7:0] ie, bit irq);
    cv_is  = is_v;
    cv_ie  = ie;
    cv_irq = irq;
    IRQ_GROUP.sample();
  endfunction

  function void report_fc();
    $display("%0t: [scoreboard] coverage: apb %0.1f%%, pin %0.1f%%, irq %0.1f%%", $time,
             APB_GROUP.get_coverage(), PIN_GROUP.get_coverage(), IRQ_GROUP.get_coverage());
  endfunction
`else
  function void sample_apb_fc(apb_packet pkt);                        endfunction
  function void sample_pin_fc(bit [7:0] rise, bit [7:0] ie);          endfunction
  function void sample_irq_fc(bit [7:0] is_v, bit [7:0] ie, bit irq); endfunction
  function void report_fc();                                          endfunction
`endif
