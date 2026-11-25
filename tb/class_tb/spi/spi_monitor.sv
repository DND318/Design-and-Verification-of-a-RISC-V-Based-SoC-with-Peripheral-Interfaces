// SPI monitor
class spi_monitor;
  virtual spi_if        dut_vif;
  mailbox #(spi_packet) m2s_mb;
  spi_cfg               cfg;

  spi_packet            pkt;
  int                   nedge;
  time                  t_edge, t_mosi, t_sample, t_e16;
  bit                   have_e16;

  function new(virtual spi_if dut_vif, mailbox #(spi_packet) m2s_mb, spi_cfg cfg);
    this.dut_vif = dut_vif;
    this.m2s_mb  = m2s_mb;
    this.cfg     = cfg;
  endfunction

  task run();
    fork
      mosi_run();
      frame_run();
    join
  endtask

  function void report(spi_packet p);
    $display("%0t: [spi_monitor] %s", $time, p.sprint());
    m2s_mb.put(p);
  endfunction

  task report_late(spi_packet p);
    fork
      begin
        automatic spi_packet q = p;
        automatic int late = p.cpha ? 4 : (p.div == 0) ? 3 : 2;
        for (int k = 0; k < late; k++) @(negedge dut_vif.clk);
        report(q);
      end
    join_none
  endtask

  // Time of the last MOSI change
  task mosi_run();
    while (1) begin
      @(dut_vif.mosi);
      t_mosi = $time;
    end
  endtask

  task frame_run();
    time       t, half_ns;
    bit        smp;
    spi_packet st;
    while (1) begin
      @(dut_vif.sclk or dut_vif.rst_n);
      t = $time;
      if (dut_vif.rst_n !== 1'b1) begin
        nedge = 0;
        have_e16 = 0;
        continue;
      end
      if (nedge == 0) begin
        if (dut_vif.sclk === cfg.cpol) continue;   // idle level change
        pkt = new();
        pkt.kind  = SPI_FRAME;
        pkt.cpol  = cfg.cpol;
        pkt.cpha  = cfg.cpha;
        pkt.lsb   = cfg.lsb;
        pkt.div   = cfg.div;
        pkt.cs_n  = dut_vif.cs_n;
        pkt.first = !have_e16;
        pkt.gap_ns = have_e16 ? t - t_e16 : 0;
        pkt.half_ok = 1; pkt.setup_ok = 1; pkt.hold_ok = 1; pkt.cs_ok = 1;
        st = new();
        st.kind = SPI_START;
        st.cpol = pkt.cpol; st.cpha = pkt.cpha; st.lsb = pkt.lsb; st.div = pkt.div;
        st.cs_n = pkt.cs_n; st.first = pkt.first; st.gap_ns = pkt.gap_ns;
        report(st);
        t_sample = 0;
      end else if (t - t_edge != (pkt.div + 1) * cfg.clk_ns) begin
        pkt.half_ok = 0;
        $display("%0t: [spi_monitor] SCLK half period %0d ns, expected %0d ns", $time, t - t_edge,
                 (pkt.div + 1) * cfg.clk_ns);
      end
      nedge++;
      t_edge  = t;
      half_ns = (pkt.div + 1) * cfg.clk_ns;
      smp     = (nedge % 2 == 1) ^ pkt.cpha;
      #1;                                          // values after this edge's updates
      if (dut_vif.cs_n !== pkt.cs_n) pkt.cs_ok = 0;
      if (smp) begin
        if (t - t_mosi < half_ns) begin
          pkt.setup_ok = 0;
          $display("%0t: [spi_monitor] MOSI setup %0d ns before sampling edge %0d, expected >= %0d ns",
                   $time, t - t_mosi, nedge, half_ns);
        end
        if (pkt.lsb) begin
          pkt.mosi = {dut_vif.mosi, pkt.mosi[7:1]};
          pkt.miso = {dut_vif.miso, pkt.miso[7:1]};
        end else begin
          pkt.mosi = {pkt.mosi[6:0], dut_vif.mosi};
          pkt.miso = {pkt.miso[6:0], dut_vif.miso};
        end
        t_sample = t;
      end else if (t_sample != 0 && t_mosi > t_sample && t_mosi - t_sample < half_ns) begin
        pkt.hold_ok = 0;
        $display("%0t: [spi_monitor] MOSI hold %0d ns after a sampling edge, expected >= %0d ns",
                 $time, t_mosi - t_sample, half_ns);
      end
      if (nedge == 16) begin
        nedge    = 0;
        t_e16    = t;
        have_e16 = 1;
        report_late(pkt);
      end
    end
  endtask
endclass
