// UART functional coverage 
`ifndef VERILATOR
  apb_packet  apb_trans;
  uart_packet frm_trans;
  bit [5:0]   cv_ier, cv_isr;

  covergroup APB_GROUP;
    apb_transfer: coverpoint apb_trans.write { bins apb_read = {0}; bins apb_write = {1}; }
    apb_address: coverpoint apb_trans.addr[11:2] {
      bins CTRL_addr   = {0};
      bins BAUD_addr   = {1};
      bins STATUS_addr = {2};
      bins TXDATA_addr = {3};
      bins RXDATA_addr = {4};
      bins IER_addr    = {5};
      bins ISR_addr    = {6};
      bins RSVD_addr   = {[7:1023]};
    }
    apb_strobe: coverpoint apb_trans.strb { bins full = {4'hF}; bins byte0 = {4'h1};
                                            bins no_byte0 = {4'h2, 4'h4, 4'h6, 4'h8, 4'hA, 4'hC, 4'hE}; }
    apb_transaction: cross apb_transfer, apb_address;
  endgroup

  covergroup FRAME_GROUP;
    frame_dir: coverpoint frm_trans.kind { bins tx = {UART_TX_FRAME}; bins rx = {UART_RX_FRAME}; }
    frame_parity: coverpoint frm_trans.par { bins none = {2'b00}; bins even = {2'b01}; bins odd = {2'b10}; }
    frame_stop: coverpoint frm_trans.stop2 { bins one = {0}; bins two = {1}; }
    frame_baud: coverpoint frm_trans.div {
      bins baud_fast    = {[0:7]};
      bins baud_medium  = {[8:63]};
      bins baud_slow    = {[64:432]};
      bins baud_115200  = {433};
      bins baud_slowest = {[434:65535]};
    }
    frame_data: coverpoint frm_trans.data { bins zero = {8'h00}; bins ones = {8'hFF}; bins other = {[8'h01:8'hFE]}; }
    frame_error: coverpoint {frm_trans.perr, frm_trans.ferr} {
      bins ok = {2'b00}; bins parity_err = {2'b10}; bins frame_err = {2'b01}; bins both = {2'b11};
    }
    format_feature: cross frame_dir, frame_parity, frame_stop;
    error_feature: cross frame_parity, frame_error {
      ignore_bins no_parity_no_perr = binsof(frame_parity.none) && binsof(frame_error.parity_err);
      ignore_bins no_parity_both    = binsof(frame_parity.none) && binsof(frame_error.both);
    }
  endgroup

  covergroup IRQ_GROUP;
    irq_enable: coverpoint cv_ier {
      bins tx_empty_ie = {6'h01}; bins rx_ne_ie = {6'h02}; bins parity_err_ie = {6'h04};
      bins frame_err_ie = {6'h08}; bins overrun_ie = {6'h10}; bins tx_ovf_ie = {6'h20};
      bins others = default;
    }
    irq_status: coverpoint cv_isr {
      bins tx_empty = {6'h01}; bins rx_ne = {6'h02}; bins parity_err = {6'h04};
      bins frame_err = {6'h08}; bins overrun = {6'h10}; bins tx_ovf = {6'h20};
      bins others = default;
    }
    irq_gating: cross irq_enable, irq_status;
  endgroup

  function void sample_apb_fc(apb_packet pkt);
    apb_trans = pkt;
    APB_GROUP.sample();
  endfunction

  function void sample_frame_fc(uart_packet pkt);
    frm_trans = pkt;
    FRAME_GROUP.sample();
  endfunction

  function void sample_irq_fc(bit [5:0] ier, bit [5:0] isr);
    cv_ier = ier;
    cv_isr = isr;
    IRQ_GROUP.sample();
  endfunction


  function void report_fc();
    $display("%0t: [scoreboard] coverage: apb %0.1f%%, frame %0.1f%%, irq %0.1f%%", $time,
             APB_GROUP.get_coverage(), FRAME_GROUP.get_coverage(), IRQ_GROUP.get_coverage());
  endfunction
`else
  function void sample_apb_fc(apb_packet pkt);              endfunction
  function void sample_frame_fc(uart_packet pkt);           endfunction
  function void sample_irq_fc(bit [5:0] ier, bit [5:0] isr); endfunction
  function void report_fc();                                endfunction
`endif
