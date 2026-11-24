// All UVM tests of the project, one include per block.
package test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import fifo_vip_pkg::*;
  import seq_pkg::*;
  import fifo_env_pkg::*;

  `include "fifo_tests.sv"
endpackage
