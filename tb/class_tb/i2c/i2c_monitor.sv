// I2C monitor
class i2c_monitor;
  virtual i2c_if        dut_vif;
  mailbox #(i2c_packet) m2s_mb;
  i2c_cfg               cfg;

  int                   nbit;           // SCL rising edges since START / last byte
  bit                   in_frame;       // after a START, until STOP
  bit [7:0]             data, m_low, s_low;
  bit                   ack, m_ack, s_ack;
  time                  t_rise, t_fall, t_start, t_stop, t_m;
  bit                   start_hold;     // SCL fall after START not seen yet
  bit                   t_ok = 1;
  string                t_msg;
  int unsigned          n_tcheck;       // timing checks made

  function new(virtual i2c_if dut_vif, mailbox #(i2c_packet) m2s_mb, i2c_cfg cfg);
    this.dut_vif = dut_vif;
    this.m2s_mb  = m2s_mb;
    this.cfg     = cfg;
  endfunction

  function void report(i2c_packet p);
    p.t_ok  = t_ok;
    p.t_msg = t_msg;
    t_ok  = 1;
    t_msg = "";
    $display("%0t: [i2c_monitor] %s", $time, p.sprint());
    m2s_mb.put(p);
  endfunction

  // One timing check (only while the DUT drives the bus)
  function void tcheck(bit ok, string what);
    if (!cfg.en) return;
    n_tcheck++;
    if (!ok) begin
      t_ok = 0;
      t_msg = {t_msg, what, "; "};
      $display("%0t: [i2c_monitor] timing: %s", $time, what);
    end
  endfunction

  task run();
    bit  scl, sda, oe;
    bit  p_scl = 1'b1, p_sda = 1'b1, p_oe = 1'b0;
    time t, q;
    i2c_packet pkt;
    while (1) begin
      @(dut_vif.scl or dut_vif.sda or dut_vif.sda_oe or dut_vif.rst_n);
      t = $time;
      q = cfg.q_ns();
      if (dut_vif.rst_n !== 1'b1) begin
        nbit = 0; in_frame = 0; start_hold = 0;
        p_scl = 1'b1; p_sda = 1'b1; p_oe = 1'b0;
        continue;
      end
      scl = dut_vif.scl;
      sda = dut_vif.sda;
      oe  = dut_vif.sda_oe;

      // master SDA change while SCL low: hold after the SCL fall
      if (oe !== p_oe) begin
        if (scl === 1'b0 && p_scl === 1'b0 && t_fall != 0)
          tcheck(t - t_fall >= q, $sformatf("tHD;DAT %0d ns < q = %0d ns", t - t_fall, q));
        t_m = t;
        p_oe = oe;
      end

      // SDA change while SCL high: START or STOP
      if (sda !== p_sda && scl === 1'b1 && p_scl === 1'b1) begin
        pkt = new();
        pkt.mid_byte = (nbit > 1);
        if (sda === 1'b0) begin
          pkt.kind = I2C_START;
          pkt.rs   = in_frame;
          if (in_frame) tcheck(t - t_rise >= q, $sformatf("tSU;STA %0d ns < q", t - t_rise));
          else if (t_stop != 0) tcheck(t - t_stop >= q, $sformatf("tBUF %0d ns < q", t - t_stop));
          in_frame   = 1;
          t_start    = t;
          start_hold = 1;
        end else begin
          pkt.kind = I2C_STOP;
          tcheck(t - t_rise >= q, $sformatf("tSU;STO %0d ns < q", t - t_rise));
          in_frame = 0;
          t_stop   = t;
        end
        nbit = 0;
        report(pkt);
      end
      p_sda = sda;

      // SCL edges
      if (scl !== p_scl) begin
        if (scl === 1'b1) begin
          if (t_fall != 0) begin
            if (nbit >= 1 && nbit <= 8)
              tcheck(t - t_fall == 2 * q, $sformatf("tLOW %0d ns, expected 2q = %0d ns", t - t_fall, 2 * q));
            else
              tcheck(t - t_fall >= 2 * q, $sformatf("tLOW %0d ns < 2q = %0d ns", t - t_fall, 2 * q));
          end
          if (t_m > t_fall)
            tcheck(t - t_m >= q, $sformatf("tSU;DAT %0d ns < q", t - t_m));
          t_rise = t;
          if (in_frame) begin
            if (nbit < 8) begin
              data  = {data[6:0], sda};
              m_low = {m_low[6:0], dut_vif.sda_oe === 1'b1};
              s_low = {s_low[6:0], dut_vif.sda_low === 1'b1};
            end else begin
              ack   = sda;
              m_ack = (dut_vif.sda_oe === 1'b1);
              s_ack = (dut_vif.sda_low === 1'b1);
            end
            nbit++;
          end
        end else begin
          if (start_hold) begin
            tcheck(t - t_start >= q, $sformatf("tHD;STA %0d ns < q", t - t_start));
            start_hold = 0;
          end
          if (nbit >= 1 && p_scl === 1'b1 && t_rise > t_start)
            tcheck(t - t_rise == 2 * q, $sformatf("tHIGH %0d ns, expected 2q = %0d ns", t - t_rise, 2 * q));
          t_fall = t;
          if (nbit == 9) begin
            pkt = new();
            pkt.kind  = I2C_BYTE;
            pkt.data  = data;
            pkt.ack   = ack;
            pkt.m_low = m_low;
            pkt.s_low = s_low;
            pkt.m_ack = m_ack;
            pkt.s_ack = s_ack;
            nbit = 0;
            report(pkt);
          end
        end
        p_scl = scl;
      end
    end
  endtask
endclass
