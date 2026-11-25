`timescale 1ns/1ps
// APB4 protocol assertions for any APB slave of the SoC (ports named as in
// CLAUDE.md). Attached with bind (sva/<block>_bind.sv). Master-side rules
// check the testbench driver, slave-side rules check the DUT.
module apb_slave_sva (
  input logic        clk_i,
  input logic        rst_ni,
  input logic        psel_i,
  input logic        penable_i,
  input logic        pwrite_i,
  input logic [11:0] paddr_i,
  input logic [31:0] pwdata_i,
  input logic [3:0]  pstrb_i,
  input logic [31:0] prdata_o,
  input logic        pready_o,
  input logic        pslverr_o
);

  // master: SETUP is always followed by ACCESS
  a_setup_then_access: assert property (@(posedge clk_i) disable iff (!rst_ni)
    (psel_i && !penable_i) |=> (psel_i && penable_i))
    else $error("SVA: APB SETUP not followed by ACCESS");

  // master: PENABLE only with PSEL
  a_penable_with_psel: assert property (@(posedge clk_i) disable iff (!rst_ni)
    penable_i |-> psel_i)
    else $error("SVA: PENABLE High without PSEL");

  // master: address, direction, data and strobes stable from SETUP to ACCESS
  a_stable_in_access: assert property (@(posedge clk_i) disable iff (!rst_ni)
    (psel_i && penable_i) |-> ($stable(paddr_i) && $stable(pwrite_i) && $stable(pwdata_i) &&
                               $stable(pstrb_i)))
    else $error("SVA: APB address/control/data changed in ACCESS");

  // master: no write strobes on a read
  a_read_no_strb: assert property (@(posedge clk_i) disable iff (!rst_ni)
    (psel_i && !pwrite_i) |-> (pstrb_i == 4'b0000))
    else $error("SVA: PSTRB not zero on a read");

  // slave: PREADY and PSLVERR known while selected
  a_pready_known: assert property (@(posedge clk_i) disable iff (!rst_ni)
    psel_i |-> !$isunknown({pready_o, pslverr_o}))
    else $error("SVA: PREADY/PSLVERR unknown while PSEL is High");

  // slave: read data known in the last ACCESS cycle of a read
  a_prdata_known: assert property (@(posedge clk_i) disable iff (!rst_ni)
    (psel_i && penable_i && !pwrite_i && pready_o) |-> !$isunknown(prdata_o))
    else $error("SVA: PRDATA unknown in read ACCESS");

  // slave: PSLVERR only in the last ACCESS cycle
  a_pslverr_in_access: assert property (@(posedge clk_i) disable iff (!rst_ni)
    pslverr_o |-> (psel_i && penable_i && pready_o))
    else $error("SVA: PSLVERR outside the ACCESS cycle");

endmodule
