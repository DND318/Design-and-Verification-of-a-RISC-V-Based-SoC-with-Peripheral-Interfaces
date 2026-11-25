// Bus tests
package test_pkg;
  import bus_pkg::*;
  `include "bus_base_test.sv"
  `include "bus_decode_test.sv"
  `include "bus_sram_test.sv"
  `include "bus_apb_test.sv"
  `include "bus_master_test.sv"
  `include "bus_rand_test.sv"
endpackage
