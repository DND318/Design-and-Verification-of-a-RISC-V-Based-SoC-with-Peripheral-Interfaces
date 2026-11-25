// GPIO tests
package test_pkg;
  import apb_vip_pkg::*;
  import gpio_pkg::*;
  `include "gpio_base_test.sv"
  `include "gpio_reg_test.sv"
  `include "gpio_input_test.sv"
  `include "gpio_irq_test.sv"
  `include "gpio_reset_test.sv"
  `include "gpio_rand_test.sv"
endpackage
