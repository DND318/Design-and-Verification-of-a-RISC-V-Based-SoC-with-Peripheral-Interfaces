// Bus environment
class bus_environment;
  bus_stimulus          stim;
  bus_driver            drv;
  cpu_monitor           cmon[2];
  axi_monitor           amon[3];
  apb_bus_monitor       pmon;
  apb_slave             pslv;
  axi_slave             aslv;
  bus_scoreboard        sb;

  mailbox #(bus_packet) s2d_mb;
  mailbox #(bus_packet) d2s_mb;
  mailbox #(bus_packet) m2s_mb;

  virtual cpu_if        cpu0_vif, cpu1_vif;
  virtual axi_if        axd_vif, ax0_vif, ax1_vif, ax2_vif;
  virtual apbm_if       apb_vif;

  function new(virtual cpu_if cpu0_vif, virtual cpu_if cpu1_vif, virtual axi_if axd_vif,
               virtual axi_if ax0_vif, virtual axi_if ax1_vif, virtual axi_if ax2_vif, virtual apbm_if apb_vif);
    this.cpu0_vif = cpu0_vif;
    this.cpu1_vif = cpu1_vif;
    this.axd_vif  = axd_vif;
    this.ax0_vif  = ax0_vif;
    this.ax1_vif  = ax1_vif;
    this.ax2_vif  = ax2_vif;
    this.apb_vif  = apb_vif;
  endfunction

  function void build();
    $display("%0t: [environment] build", $time);
    s2d_mb = new();
    d2s_mb = new();
    m2s_mb = new();
    stim    = new(s2d_mb, d2s_mb);
    drv     = new(cpu0_vif, cpu1_vif, axd_vif, s2d_mb, d2s_mb);
    cmon[0] = new(cpu0_vif, m2s_mb, 0);
    cmon[1] = new(cpu1_vif, m2s_mb, 1);
    amon[0] = new(ax0_vif, m2s_mb, 0, 1'b1, 2);
    amon[1] = new(ax1_vif, m2s_mb, 1, 1'b0, 0);
    amon[2] = new(ax2_vif, m2s_mb, 2, 1'b1, 2);
    pmon    = new(apb_vif, m2s_mb);
    pslv    = new(apb_vif);
    aslv    = new(ax2_vif);
    sb      = new(m2s_mb);
  endfunction

  task run();
    $display("%0t: [environment] run", $time);
    fork
      stim.run();
      drv.run();
      cmon[0].run();
      cmon[1].run();
      amon[0].run();
      amon[1].run();
      amon[2].run();
      pmon.run();
      pslv.run();
      aslv.run();
      sb.run();
    join_none
  endtask

  // Let the monitors and the scoreboard catch up with the DUT
  task flush();
    repeat (2) @(posedge cpu0_vif.clk);
    #5ns;
  endtask
endclass
