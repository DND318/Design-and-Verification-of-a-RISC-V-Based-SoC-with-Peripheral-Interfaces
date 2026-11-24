// APB verification IP for the class-based testbenches (no UVM):
// packet, stimulus, driver and monitor. The block-specific scoreboard,
// environment and tests live in tb/class_tb/<block>/ and testcases/<block>/.
package apb_vip_pkg;
  `include "apb_packet.sv"
  `include "apb_stimulus.sv"
  `include "apb_driver.sv"
  `include "apb_monitor.sv"
endpackage
