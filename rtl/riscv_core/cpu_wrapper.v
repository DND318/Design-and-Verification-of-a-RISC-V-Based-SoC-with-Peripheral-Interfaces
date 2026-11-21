`timescale 1ns/1ps
module cpu_wrapper #(
  parameter [31:0] BOOT_ADDR = 32'h0000_0000
) (
  input  wire        clk_i,
  input  wire        rst_ni,

  output wire        mem_req_o,
  output wire        mem_instr_o,
  output wire        mem_we_o,
  output wire [3:0]  mem_wstrb_o,
  output wire [31:0] mem_addr_o,
  output wire [31:0] mem_wdata_o,
  input  wire [31:0] mem_rdata_i,
  input  wire        mem_ready_i,
  input  wire        mem_err_i,

  input  wire        irq_mtip_i,
  input  wire        irq_meip_i
);

  rv32_core #(
    .BOOT_ADDR (BOOT_ADDR)
  ) u_core (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .mem_req_o   (mem_req_o),
    .mem_instr_o (mem_instr_o),
    .mem_we_o    (mem_we_o),
    .mem_wstrb_o (mem_wstrb_o),
    .mem_addr_o  (mem_addr_o),
    .mem_wdata_o (mem_wdata_o),
    .mem_rdata_i (mem_rdata_i),
    .mem_ready_i (mem_ready_i),
    .mem_err_i   (mem_err_i),
    .irq_mtip_i  (irq_mtip_i),
    .irq_meip_i  (irq_meip_i)
  );

endmodule
