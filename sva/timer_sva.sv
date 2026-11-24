`timescale 1ns/1ps
// Timer-specific assertions. Attached with bind in sva/timer_bind.sv.
module timer_sva (
  input logic clk_i,
  input logic rst_ni,
  input logic irq_mtip_o
);
  a_irq_known: assert property (@(posedge clk_i) disable iff (!rst_ni)
    !$isunknown(irq_mtip_o))
    else $error("SVA: irq_mtip_o unknown");

  // the irq output is registered: it changes only at a clock edge
  a_irq_low_in_reset: assert property (@(posedge clk_i)
    !rst_ni |-> !irq_mtip_o)
    else $error("SVA: irq_mtip_o High during reset");
endmodule
