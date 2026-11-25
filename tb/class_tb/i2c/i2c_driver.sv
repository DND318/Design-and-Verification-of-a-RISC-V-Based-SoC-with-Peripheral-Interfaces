// I2C driver
class i2c_driver;
  mailbox #(i2c_packet) s2d_mb;
  mailbox #(i2c_packet) d2s_mb;
  virtual i2c_if        dut_vif;

  localparam int ST_IDLE = 0;   // standby: wait for START
  localparam int ST_CTRL = 1;   // receiving the control byte
  localparam int ST_ADRH = 2;   // receiving the address high byte
  localparam int ST_ADRL = 3;   // receiving the address low byte
  localparam int ST_WDAT = 4;   // receiving data bytes
  localparam int ST_RDAT = 5;   // sending data bytes

  // slave settings
  bit [6:0]    dev_addr = 7'h50;
  int unsigned twc_ns   = 10_000;
  int unsigned taa_ns   = 5;

  // slave state
  bit [7:0]    mem  [4096];
  bit [7:0]    pbuf [32];
  bit          pval [32];
  int          st;
  int          cnt;              // SCL rising edges inside the current byte (1..9)
  bit [7:0]    shreg, txbyte;
  bit [11:0]   ptr, waddr;
  bit          rw, acked, mack;
  int          nwr;
  time         wc_end;
  int unsigned n_write_cycles, n_ctrl_nacked;

  function new(virtual i2c_if dut_vif, mailbox #(i2c_packet) s2d_mb, mailbox #(i2c_packet) d2s_mb);
    this.dut_vif = dut_vif;
    this.s2d_mb  = s2d_mb;
    this.d2s_mb  = d2s_mb;
    for (int i = 0; i < 4096; i++) mem[i] = pattern(i);
  endfunction

  static function bit [7:0] pattern(input int a);
    return 8'((a * 37 + (a >> 8) * 11 + 5) & 255);
  endfunction

  task run();
    dut_vif.sda_low     = 1'b0;
    dut_vif.ext_scl_low = 1'b0;
    dut_vif.ext_sda_low = 1'b0;
    fork
      pkt_run();
      slave_run();
    join
  endtask

  // ---------------------------------------------------------------- packets
  task pkt_run();
    i2c_packet pkt;
    while (1) begin
      s2d_mb.get(pkt);
      $display("%0t: [i2c_driver] Get packet from stimulus: %s", $time, pkt.sprint());
      case (pkt.kind)
        I2C_SLAVE_CFG: begin
          dev_addr = pkt.dev_addr;
          twc_ns   = pkt.twc_ns;
          taa_ns   = pkt.taa_ns;
        end
        I2C_EXT_START: begin                     // SDA low, then SCL low
          dut_vif.ext_sda_low = 1'b1;
          #(pkt.ext_ns);
          dut_vif.ext_scl_low = 1'b1;
          #(pkt.ext_ns);
        end
        I2C_EXT_STOP: begin                      // SDA low, SCL released, then SDA released
          dut_vif.ext_sda_low = 1'b1;
          #(pkt.ext_ns);
          dut_vif.ext_scl_low = 1'b0;
          #(pkt.ext_ns);
          dut_vif.ext_sda_low = 1'b0;
          #(pkt.ext_ns);
        end
        default: ;
      endcase
      d2s_mb.put(pkt);                           // done
    end
  endtask

  // ---------------------------------------------------------------- slave
  // SDA output, taa_ns after now (in the background: the next SCL edge comes
  // at least one quarter period later)
  task drive(input bit low);
    fork
      begin
        automatic bit v = low;
        #(taa_ns);
        dut_vif.sda_low = v;
      end
    join_none
  endtask

  task slave_run();
    bit scl, sda;
    bit p_scl = 1'b1, p_sda = 1'b1;
    while (1) begin
      @(dut_vif.scl or dut_vif.sda);
      scl = dut_vif.scl;
      sda = dut_vif.sda;
      if (sda !== p_sda && scl === 1'b1 && p_scl === 1'b1) begin
        if (sda === 1'b0) on_start();
        else              on_stop();
      end
      if (scl !== p_scl) begin
        if (scl === 1'b1) on_rise(sda);
        else              on_fall();
      end
      p_scl = scl;
      p_sda = sda;
    end
  endtask

  // START: uncommitted page data is discarded
  function void on_start();
    st  = ST_CTRL;
    cnt = 0;
    nwr = 0;
    foreach (pval[i]) pval[i] = 1'b0;
    dut_vif.sda_low = 1'b0;
  endfunction

  // STOP: starts the internal write cycle
  function void on_stop();
    if (st == ST_WDAT && nwr > 0) begin
      foreach (pval[i])
        if (pval[i]) mem[{waddr[11:5], 5'(i)}] = pbuf[i];
      ptr    = waddr;
      wc_end = $time + twc_ns;
      n_write_cycles++;
    end
    foreach (pval[i]) pval[i] = 1'b0;
    nwr = 0;
    st  = ST_IDLE;
    cnt = 0;
    dut_vif.sda_low = 1'b0;
  endfunction

  function void on_rise(bit sda);
    if (st == ST_IDLE) return;
    cnt++;
    if (cnt <= 8)            shreg = {shreg[6:0], sda};
    else if (st == ST_RDAT)  mack  = (sda == 1'b0);
  endfunction

  task on_fall();
    if (st == ST_IDLE) return;
    if (cnt == 8) begin
      // end of the 8th bit: ACK the received byte, or release SDA for the master ACK
      if (st == ST_RDAT) begin
        drive(1'b0);
      end else begin
        acked = 1'b1;
        case (st)
          ST_CTRL: begin
            if (shreg[7:1] != dev_addr || $time < wc_end) begin
              acked = 1'b0;
              n_ctrl_nacked++;
            end else begin
              rw = shreg[0];
            end
          end
          ST_ADRH: waddr[11:8] = shreg[3:0];
          ST_ADRL: begin
            waddr[7:0] = shreg;
            ptr = waddr;
          end
          default: begin                         // ST_WDAT
            pbuf[waddr[4:0]] = shreg;
            pval[waddr[4:0]] = 1'b1;
            waddr[4:0] = waddr[4:0] + 5'd1;
            nwr++;
          end
        endcase
        drive(acked);
      end
    end else if (cnt == 9) begin
      // end of the ACK clock
      cnt = 0;
      case (st)
        ST_CTRL: begin
          if (!acked) begin
            st = ST_IDLE;
            drive(1'b0);
          end else if (rw) begin
            st = ST_RDAT;
            txbyte = mem[ptr];
            drive(~txbyte[7]);
          end else begin
            st = ST_ADRH;
            drive(1'b0);
          end
        end
        ST_ADRH: begin
          st = ST_ADRL;
          drive(1'b0);
        end
        ST_ADRL: begin
          st = ST_WDAT;
          drive(1'b0);
        end
        ST_WDAT: drive(1'b0);
        default: begin                           // ST_RDAT
          ptr = ptr + 12'd1;
          if (mack) begin
            txbyte = mem[ptr];
            drive(~txbyte[7]);
          end else begin
            st = ST_IDLE;
            drive(1'b0);
          end
        end
      endcase
    end else if (st == ST_RDAT && cnt >= 1 && cnt <= 7) begin
      drive(~txbyte[7 - cnt]);
    end
  endtask
endclass
