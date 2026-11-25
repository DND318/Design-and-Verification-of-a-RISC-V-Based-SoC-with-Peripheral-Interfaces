// SPI functional coverage (included in the scoreboard)
`ifndef VERILATOR
  apb_packet apb_trans;
  spi_packet frm_trans;
  bit [1:0]  cv_ier, cv_isr;

  covergroup APB_GROUP;
    apb_transfer: coverpoint apb_trans.write { bins apb_read = {0}; bins apb_write = {1}; }
    apb_address: coverpoint apb_trans.addr[11:2] {
      bins CTRL_addr   = {0};
      bins CLKDIV_addr = {1};
      bins CS_addr     = {2};
      bins STATUS_addr = {3};
      bins TXDATA_addr = {4};
      bins RXDATA_addr = {5};
      bins IER_addr    = {6};
      bins ISR_addr    = {7};
      bins RSVD_addr   = {[8:1023]};
    }
    apb_strobe: coverpoint apb_trans.strb { bins full = {4'hF}; bins byte0 = {4'h1};
                                            bins no_byte0 = {4'h2, 4'h4, 4'h6, 4'h8, 4'hA, 4'hC, 4'hE}; }
    apb_transaction: cross apb_transfer, apb_address;
  endgroup

  covergroup FRAME_GROUP;
    frame_mode: coverpoint {frm_trans.cpol, frm_trans.cpha} { bins mode0 = {0}; bins mode1 = {1};
                                                              bins mode2 = {2}; bins mode3 = {3}; }
    frame_order: coverpoint frm_trans.lsb { bins msb_first = {0}; bins lsb_first = {1}; }
    frame_div: coverpoint frm_trans.div {
      bins div_0      = {0};
      bins div_1      = {1};
      bins div_small  = {[2:11]};
      bins div_12     = {12};
      bins div_large  = {[13:254]};
      bins div_255    = {255};
    }
    frame_cs: coverpoint frm_trans.cs_n { bins selected = {0}; bins not_selected = {1}; }
    frame_mosi: coverpoint frm_trans.mosi { bins zero = {8'h00}; bins ones = {8'hFF}; bins other = {[8'h01:8'hFE]}; }
    frame_miso: coverpoint frm_trans.miso { bins zero = {8'h00}; bins ones = {8'hFF}; bins other = {[8'h01:8'hFE]}; }
    mode_feature: cross frame_mode, frame_order;
  endgroup

  covergroup IRQ_GROUP;
    irq_enable: coverpoint cv_ier { bins none = {0}; bins done_ie = {1}; bins rx_ovr_ie = {2}; bins both = {3}; }
    irq_status: coverpoint cv_isr { bins none = {0}; bins done = {1}; bins rx_ovr = {2}; bins both = {3}; }
    irq_gating: cross irq_enable, irq_status;
  endgroup

  function void sample_apb_fc(apb_packet pkt);
    apb_trans = pkt;
    APB_GROUP.sample();
  endfunction

  function void sample_frame_fc(spi_packet pkt);
    frm_trans = pkt;
    FRAME_GROUP.sample();
  endfunction

  function void sample_irq_fc(bit [1:0] ier, bit [1:0] isr);
    cv_ier = ier;
    cv_isr = isr;
    IRQ_GROUP.sample();
  endfunction

  function void report_fc();
    $display("%0t: [scoreboard] coverage: apb %0.1f%%, frame %0.1f%%, irq %0.1f%%", $time,
             APB_GROUP.get_coverage(), FRAME_GROUP.get_coverage(), IRQ_GROUP.get_coverage());
  endfunction
`else
  function void sample_apb_fc(apb_packet pkt);               endfunction
  function void sample_frame_fc(spi_packet pkt);             endfunction
  function void sample_irq_fc(bit [1:0] ier, bit [1:0] isr); endfunction
  function void report_fc();                                 endfunction
`endif
