// I2C functional coverage 
`ifndef VERILATOR
  apb_packet apb_trans;
  bit [4:0]  cv_cmd;
  bit        cv_wr, cv_ack;
  bit [1:0]  cv_ier, cv_isr;

  covergroup APB_GROUP;
    apb_transfer: coverpoint apb_trans.write { bins apb_read = {0}; bins apb_write = {1}; }
    apb_address: coverpoint apb_trans.addr[11:2] {
      bins CTRL_addr     = {0};
      bins PRESCALE_addr = {1};
      bins CMD_addr      = {2};
      bins TXDATA_addr   = {3};
      bins RXDATA_addr   = {4};
      bins STATUS_addr   = {5};
      bins IER_addr      = {6};
      bins ISR_addr      = {7};
      bins RSVD_addr     = {[8:1023]};
    }
    apb_strobe: coverpoint apb_trans.strb { bins full = {4'hF}; bins byte0 = {4'h1};
                                            bins no_byte0 = {4'h2, 4'h4, 4'h6, 4'h8, 4'hA, 4'hC, 4'hE}; }
    apb_transaction: cross apb_transfer, apb_address;
  endgroup

  // CMD bits {nack, read, write, stop, start} of every command taken
  covergroup CMD_GROUP;
    cmd: coverpoint cv_cmd {
      bins start_only      = {5'b00001};
      bins stop_only       = {5'b00010};
      bins start_stop      = {5'b00011};
      bins write           = {5'b00100};
      bins start_write     = {5'b00101};
      bins write_stop      = {5'b00110};
      bins start_write_stop= {5'b00111};
      bins read_ack        = {5'b01000};
      bins start_read      = {5'b01001};
      bins read_nack       = {5'b11000};
      bins read_nack_stop  = {5'b11010};
      bins others          = default;
    }
  endgroup

  covergroup BYTE_GROUP;
    byte_dir: coverpoint cv_wr { bins read = {0}; bins write = {1}; }
    byte_ack: coverpoint cv_ack { bins ack = {0}; bins nack = {1}; }
    dir_ack: cross byte_dir, byte_ack;
  endgroup

  covergroup IRQ_GROUP;
    irq_enable: coverpoint cv_ier { bins none = {0}; bins done_ie = {1}; bins nack_ie = {2}; bins both = {3}; }
    irq_status: coverpoint cv_isr { bins none = {0}; bins done = {1}; bins nack = {2}; bins both = {3}; }
    irq_gating: cross irq_enable, irq_status;
  endgroup

  function void sample_apb_fc(apb_packet pkt);
    apb_trans = pkt;
    APB_GROUP.sample();
  endfunction

  function void sample_cmd_fc(bit [4:0] c);
    cv_cmd = c;
    CMD_GROUP.sample();
  endfunction

  function void sample_byte_fc(bit wr, bit ack);
    cv_wr  = wr;
    cv_ack = ack;
    BYTE_GROUP.sample();
  endfunction

  function void sample_irq_fc(bit [1:0] ier, bit [1:0] isr);
    cv_ier = ier;
    cv_isr = isr;
    IRQ_GROUP.sample();
  endfunction

  function void report_fc();
    $display("%0t: [scoreboard] coverage: apb %0.1f%%, cmd %0.1f%%, byte %0.1f%%, irq %0.1f%%", $time,
             APB_GROUP.get_coverage(), CMD_GROUP.get_coverage(), BYTE_GROUP.get_coverage(), IRQ_GROUP.get_coverage());
  endfunction
`else
  function void sample_apb_fc(apb_packet pkt);               endfunction
  function void sample_cmd_fc(bit [4:0] c);                  endfunction
  function void sample_byte_fc(bit wr, bit ack);             endfunction
  function void sample_irq_fc(bit [1:0] ier, bit [1:0] isr); endfunction
  function void report_fc();                                 endfunction
`endif
