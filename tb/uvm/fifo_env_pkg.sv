// Environment of the sync_fifo testbench: agent + scoreboard + coverage.
package fifo_env_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import fifo_vip_pkg::*;

  `include "fifo_scoreboard.sv"
  `include "fifo_coverage.sv"
  `include "fifo_env.sv"
endpackage
