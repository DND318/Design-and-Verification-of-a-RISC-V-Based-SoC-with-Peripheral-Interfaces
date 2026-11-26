// IRQC tests
package test_pkg;
  import apb_vip_pkg::*;
  import irqc_pkg::*;
  `include "irqc_base_test.sv"
  `include "irqc_reg_test.sv"
  `include "irqc_func_test.sv"
  `include "irqc_prio_test.sv"
  `include "irqc_reset_test.sv"
  `include "irqc_rand_test.sv"
endpackage
