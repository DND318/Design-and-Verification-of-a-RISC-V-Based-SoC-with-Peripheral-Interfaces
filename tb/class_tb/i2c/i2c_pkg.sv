// I2C testbench package
package i2c_pkg;
  import apb_vip_pkg::*;

  `include "i2c_packet.sv"
  `include "i2c_stimulus.sv"
  `include "i2c_driver.sv"
  `include "i2c_monitor.sv"
  `include "i2c_scoreboard.sv"
  `include "i2c_environment.sv"
endpackage
