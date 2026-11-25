// UART tests
package test_pkg;
  import apb_vip_pkg::*;
  import uart_pkg::*;
  `include "uart_base_test.sv"
  `include "uart_reg_test.sv"
  `include "uart_tx_test.sv"
  `include "uart_rx_test.sv"
  `include "uart_loopback_test.sv"
  `include "uart_irq_test.sv"
  `include "uart_rand_test.sv"
endpackage
