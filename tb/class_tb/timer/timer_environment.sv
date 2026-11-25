// Timer environment
class timer_environment;
  virtual apb_if        vif;
  mailbox #(apb_packet) s2d_mb;
  mailbox #(apb_packet) d2s_mb;
  mailbox #(apb_packet) m2s_mb;
  apb_stimulus          stim;
  apb_driver            drv;
  apb_monitor           mon;
  timer_scoreboard      sb;

  function new(virtual apb_if vif);
    this.vif = vif;
  endfunction

  function void build();
    $display("%0t: [environment] build", $time);
    s2d_mb = new();
    d2s_mb = new();
    m2s_mb = new();
    stim   = new(s2d_mb, d2s_mb);
    drv    = new(vif, s2d_mb, d2s_mb);
    mon    = new(vif, m2s_mb);
    sb     = new(m2s_mb);
  endfunction

  task run();
    $display("%0t: [environment] run", $time);
    fork
      drv.run();
      mon.run();
      sb.run();
    join_none
  endtask

  // Let the scoreboard catch up with the DUT (one clock)
  task flush();
    mon.flush_req = 1'b1;
    stim.idle(1);
  endtask
endclass
