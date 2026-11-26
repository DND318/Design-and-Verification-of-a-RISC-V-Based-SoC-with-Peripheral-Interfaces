// IRQC testbench package
package irqc_pkg;
  import apb_vip_pkg::*;

  `include "irqc_packet.sv"
  `include "irqc_stimulus.sv"
  `include "irqc_driver.sv"
  `include "irqc_monitor.sv"
  `include "irqc_scoreboard.sv"
  `include "irqc_environment.sv"
endpackage
