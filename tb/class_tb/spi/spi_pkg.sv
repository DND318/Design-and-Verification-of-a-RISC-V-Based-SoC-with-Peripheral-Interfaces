// SPI testbench package
package spi_pkg;
  import apb_vip_pkg::*;

  `include "spi_packet.sv"
  `include "spi_stimulus.sv"
  `include "spi_driver.sv"
  `include "spi_monitor.sv"
  `include "spi_scoreboard.sv"
  `include "spi_environment.sv"
endpackage
