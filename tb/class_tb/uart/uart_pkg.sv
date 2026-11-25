// UART testbench package
package uart_pkg;
  import apb_vip_pkg::*;

  `include "uart_packet.sv"
  `include "uart_stimulus.sv"
  `include "uart_driver.sv"
  `include "uart_monitor.sv"
  `include "uart_scoreboard.sv"
  `include "uart_environment.sv"
endpackage
