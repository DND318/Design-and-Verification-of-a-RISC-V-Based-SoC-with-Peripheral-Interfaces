// I2C tests
package test_pkg;
  import apb_vip_pkg::*;
  import i2c_pkg::*;
  `include "i2c_base_test.sv"
  `include "i2c_reg_test.sv"
  `include "i2c_write_test.sv"
  `include "i2c_read_test.sv"
  `include "i2c_bus_test.sv"
  `include "i2c_irq_test.sv"
  `include "i2c_rand_test.sv"
endpackage
