// GPIO environment
class gpio_environment;
  apb_stimulus           apb_stim;
  apb_driver             apb_drv;
  apb_monitor            apb_mon;
  gpio_stimulus          stim;
  gpio_driver            drv;
  gpio_monitor           mon;
  gpio_scoreboard        sb;

  mailbox #(apb_packet)  apb_s2d_mb;
  mailbox #(apb_packet)  apb_d2s_mb;
  mailbox #(apb_packet)  apb_m2s_mb;
  mailbox #(gpio_packet) s2d_mb;
  mailbox #(gpio_packet) d2s_mb;
  mailbox #(gpio_packet) m2s_mb;

  virtual apb_if         apb_vif;
  virtual gpio_if        gpio_vif;

  function new(virtual apb_if apb_vif, virtual gpio_if gpio_vif);
    this.apb_vif  = apb_vif;
    this.gpio_vif = gpio_vif;
  endfunction

  function void build();
    $display("%0t: [environment] build", $time);
    apb_s2d_mb = new();
    apb_d2s_mb = new();
    apb_m2s_mb = new();
    s2d_mb     = new();
    d2s_mb     = new();
    m2s_mb     = new();

    apb_stim = new(apb_s2d_mb, apb_d2s_mb);
    apb_drv  = new(apb_vif, apb_s2d_mb, apb_d2s_mb);
    apb_mon  = new(apb_vif, apb_m2s_mb);
    stim     = new(s2d_mb, d2s_mb);
    drv      = new(gpio_vif, s2d_mb, d2s_mb);
    mon      = new(gpio_vif, m2s_mb);
    sb       = new(apb_m2s_mb, m2s_mb);
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

  // Let the scoreboard catch up with the DUT (two clocks)
  task flush();
    apb_stim.idle(2);
  endtask
endclass
