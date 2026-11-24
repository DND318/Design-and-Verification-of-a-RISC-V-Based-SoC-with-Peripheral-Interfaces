// Reusable FIFO verification IP: transaction, driver, monitor, agent.
package fifo_vip_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int unsigned WIDTH = 8;
  localparam int unsigned DEPTH = 16;

  `include "fifo_item.sv"
  `include "fifo_driver.sv"
  `include "fifo_monitor.sv"
  `include "fifo_agent.sv"
endpackage
