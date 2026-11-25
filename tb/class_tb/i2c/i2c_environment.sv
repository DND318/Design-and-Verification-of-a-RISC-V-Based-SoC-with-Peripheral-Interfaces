// I2C environment
class i2c_environment;
  apb_stimulus          apb_stim;
  apb_driver            apb_drv;
  apb_monitor           apb_mon;
  i2c_stimulus          stim;
  i2c_driver            drv;
  i2c_monitor           mon;
  i2c_scoreboard        sb;
  i2c_cfg               cfg;

  mailbox #(apb_packet) apb_s2d_mb;
  mailbox #(apb_packet) apb_d2s_mb;
  mailbox #(apb_packet) apb_m2s_mb;
  mailbox #(i2c_packet) s2d_mb;
  mailbox #(i2c_packet) d2s_mb;
  mailbox #(i2c_packet) m2s_mb;

  virtual apb_if        apb_vif;
  virtual i2c_if        i2c_vif;

  function new(virtual apb_if apb_vif, virtual i2c_if i2c_vif);
    this.apb_vif = apb_vif;
    this.i2c_vif = i2c_vif;
  endfunction

  function void build();
    $display("%0t: [environment] build", $time);
    apb_s2d_mb = new();
    apb_d2s_mb = new();
    apb_m2s_mb = new();
    s2d_mb     = new();
    d2s_mb     = new();
    m2s_mb     = new();
    cfg        = new();

    apb_stim = new(apb_s2d_mb, apb_d2s_mb);
    apb_drv  = new(apb_vif, apb_s2d_mb, apb_d2s_mb);
    apb_mon  = new(apb_vif, apb_m2s_mb);
    stim     = new(s2d_mb, d2s_mb);
    drv      = new(i2c_vif, s2d_mb, d2s_mb);
    mon      = new(i2c_vif, m2s_mb, cfg);
    sb       = new(apb_m2s_mb, m2s_mb, cfg);
  endfunction

  task run();
    $display("%0t: [environment] run", $time);
    fork
      apb_drv.run();
      apb_mon.run();
      stim.run();
      drv.run();
      mon.run();
      sb.run();
    join_none
  endtask

  // Let the scoreboard catch up with the DUT (one clock)
  task flush();
    apb_mon.flush_req = 1'b1;
    apb_stim.idle(1);
  endtask
endclass
