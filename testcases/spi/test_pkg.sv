// SPI tests
package test_pkg;
  import apb_vip_pkg::*;
  import spi_pkg::*;
  `include "spi_base_test.sv"
  `include "spi_reg_test.sv"
  `include "spi_mode_test.sv"
  `include "spi_timing_test.sv"
  `include "spi_fifo_test.sv"
  `include "spi_irq_test.sv"
  `include "spi_rand_test.sv"
endpackage
