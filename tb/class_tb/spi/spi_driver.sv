// SPI driver: SPI slave model on MISO
class spi_driver;
  mailbox #(spi_packet) s2d_mb;
  mailbox #(spi_packet) d2s_mb;
  virtual spi_if        dut_vif;
  spi_cfg               cfg;

  spi_packet            cur;
  bit                   cur_stim;       // cur came from the stimulus (not a random filler)
  spi_packet            back_q[$];      // bytes given back when CS rose
  int                   nedge;          // SCLK edges in this frame
  int                   bitn;           // next bit to drive
  bit                   preloaded;      // CPHA 0: bit 0 driven, no edge yet
  bit                   prev_cs, prev_sclk;

  function new(virtual spi_if dut_vif, mailbox #(spi_packet) s2d_mb, mailbox #(spi_packet) d2s_mb,
               spi_cfg cfg);
    this.dut_vif = dut_vif;
    this.s2d_mb  = s2d_mb;
    this.d2s_mb  = d2s_mb;
    this.cfg     = cfg;
  endfunction

  function void load();
    cur_stim = 1;
    if (back_q.size() != 0) begin
      cur = back_q.pop_front();
    end else if (s2d_mb.try_get(cur)) begin
      $display("%0t: [spi_driver] Get packet from stimulus: %s", $time, cur.sprint());
    end else begin
      cur = new();
      cur.data = 8'($urandom);
      cur_stim = 0;
    end
    bitn = 0;
  endfunction

  task drive_bit();
    bit v = cfg.lsb ? cur.data[bitn] : cur.data[7 - bitn];
    bitn++;
    #(cfg.miso_dly);
    dut_vif.miso = v;
  endtask

  task release_bus();
    #(cfg.miso_dly);
    dut_vif.miso = 1'b1;
  endtask

  task run();
    dut_vif.miso = 1'b1;
    prev_cs   = 1'b1;
    prev_sclk = 1'b0;
    while (1) begin
      @(dut_vif.sclk or dut_vif.cs_n or dut_vif.rst_n);
      if (dut_vif.rst_n !== 1'b1) begin
        nedge = 0; preloaded = 0; prev_cs = 1'b1; prev_sclk = dut_vif.sclk;
        dut_vif.miso = 1'b1;
        continue;
      end
      if (dut_vif.cs_n !== prev_cs) begin
        prev_cs = dut_vif.cs_n;
        nedge   = 0;
        if (prev_cs) begin                        // CS released
          if (preloaded && cur_stim) back_q.push_front(cur);
          preloaded = 0;
          release_bus();
        end else if (!cfg.cpha) begin             // CS asserted, CPHA 0: first bit now
          load();
          preloaded = 1;
          drive_bit();
        end
      end
      if (dut_vif.sclk !== prev_sclk) begin
        prev_sclk = dut_vif.sclk;
        if (dut_vif.cs_n !== 1'b0) continue;
        if (nedge == 0 && dut_vif.sclk === cfg.cpol) continue;   // idle level change (CPOL written)
        nedge++;
        preloaded = 0;
        if (cfg.cpha) begin
          if (nedge % 2 == 1) begin
            if (nedge == 1) load();
            drive_bit();
          end
        end else if (nedge % 2 == 0 && nedge < 16) begin
          drive_bit();
        end
        if (nedge == 16) begin
          nedge = 0;
          if (cur_stim) d2s_mb.put(cur);          // done
          if (!cfg.cpha) begin                    // next frame: first bit now
            load();
            preloaded = 1;
            drive_bit();
          end
        end
      end
    end
  endtask
endclass
