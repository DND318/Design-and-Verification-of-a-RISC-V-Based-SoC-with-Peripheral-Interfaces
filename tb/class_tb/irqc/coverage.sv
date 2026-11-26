// IRQC functional coverage (included in the scoreboard)
`ifndef VERILATOR
  apb_packet apb_trans;
  bit [3:0]  cv_lines, cv_en;

  covergroup APB_GROUP;
    apb_transfer: coverpoint apb_trans.write { bins apb_read = {0}; bins apb_write = {1}; }
    apb_address: coverpoint apb_trans.addr[11:2] {
      bins PENDING_addr = {0};
      bins ENABLE_addr  = {1};
      bins STATUS_addr  = {2};
      bins ID_addr      = {3};
      bins RSVD_addr    = {[4:1023]};
    }
    apb_transaction: cross apb_transfer, apb_address;
  endgroup

  // every pending x enable combination (IRQC-16) and every ID value (IRQC-17)
  covergroup IRQ_GROUP;
    pending: coverpoint cv_lines { bins p[] = {[0:15]}; }
    enable:  coverpoint cv_en    { bins e[] = {[0:15]}; }
    pending_x_enable: cross pending, enable;
    id: coverpoint irq_id(cv_lines & cv_en) { bins none = {0}; bins uart = {1}; bins spi = {2};
                                              bins i2c = {3}; bins gpio = {4}; }
  endgroup

  function void sample_apb_fc(apb_packet pkt);
    apb_trans = pkt;
    APB_GROUP.sample();
  endfunction

  function void sample_irq_fc(bit [3:0] lines, bit [3:0] en);
    cv_lines = lines;
    cv_en    = en;
    IRQ_GROUP.sample();
  endfunction

  function void report_fc();
    $display("%0t: [scoreboard] coverage: apb %0.1f%%, irq %0.1f%%", $time,
             APB_GROUP.get_coverage(), IRQ_GROUP.get_coverage());
  endfunction
`else
  function void sample_apb_fc(apb_packet pkt);              endfunction
  function void sample_irq_fc(bit [3:0] lines, bit [3:0] en); endfunction
  function void report_fc();                                endfunction
`endif
