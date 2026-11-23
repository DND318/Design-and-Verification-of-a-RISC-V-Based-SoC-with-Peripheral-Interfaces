`timescale 1ns/1ps
module axi_lite_xbar_1x2 (
  input  wire        clk_i,
  input  wire        rst_ni,

  // Slave port (from the master adapter)
  input  wire [31:0] s_awaddr_i,
  input  wire [2:0]  s_awprot_i,
  input  wire        s_awvalid_i,
  output reg         s_awready_o,
  input  wire [31:0] s_wdata_i,
  input  wire [3:0]  s_wstrb_i,
  input  wire        s_wvalid_i,
  output reg         s_wready_o,
  output reg  [1:0]  s_bresp_o,
  output reg         s_bvalid_o,
  input  wire        s_bready_i,
  input  wire [31:0] s_araddr_i,
  input  wire [2:0]  s_arprot_i,
  input  wire        s_arvalid_i,
  output reg         s_arready_o,
  output reg  [31:0] s_rdata_o,
  output reg  [1:0]  s_rresp_o,
  output reg         s_rvalid_o,
  input  wire        s_rready_i,

  // Master port 0 (SRAM)
  output wire [31:0] m0_awaddr_o,
  output wire [2:0]  m0_awprot_o,
  output wire        m0_awvalid_o,
  input  wire        m0_awready_i,
  output wire [31:0] m0_wdata_o,
  output wire [3:0]  m0_wstrb_o,
  output wire        m0_wvalid_o,
  input  wire        m0_wready_i,
  input  wire [1:0]  m0_bresp_i,
  input  wire        m0_bvalid_i,
  output wire        m0_bready_o,
  output wire [31:0] m0_araddr_o,
  output wire [2:0]  m0_arprot_o,
  output wire        m0_arvalid_o,
  input  wire        m0_arready_i,
  input  wire [31:0] m0_rdata_i,
  input  wire [1:0]  m0_rresp_i,
  input  wire        m0_rvalid_i,
  output wire        m0_rready_o,

  // Master port 1 (AXI4-Lite to APB bridge)
  output wire [31:0] m1_awaddr_o,
  output wire [2:0]  m1_awprot_o,
  output wire        m1_awvalid_o,
  input  wire        m1_awready_i,
  output wire [31:0] m1_wdata_o,
  output wire [3:0]  m1_wstrb_o,
  output wire        m1_wvalid_o,
  input  wire        m1_wready_i,
  input  wire [1:0]  m1_bresp_i,
  input  wire        m1_bvalid_i,
  output wire        m1_bready_o,
  output wire [31:0] m1_araddr_o,
  output wire [2:0]  m1_arprot_o,
  output wire        m1_arvalid_o,
  input  wire        m1_arready_i,
  input  wire [31:0] m1_rdata_i,
  input  wire [1:0]  m1_rresp_i,
  input  wire        m1_rvalid_i,
  output wire        m1_rready_o
);

  localparam [1:0] T_SRAM = 2'd0,
                   T_APB  = 2'd1,
                   T_ERR  = 2'd2;

  localparam [1:0] RESP_DECERR = 2'b11;

  function [1:0] decode;
    input [31:14] addr;
    begin
      if (addr[31:14] <= 18'd1)          decode = T_SRAM;
      else if (addr[31:16] == 16'h1000)  decode = T_APB;
      else                               decode = T_ERR;
    end
  endfunction

  // ---------------- write channels ----------------
  reg        w_act_q;          // AW accepted, waiting for B
  reg  [1:0] w_tgt_q;
  reg        w_done_q;         // W accepted (for the default slave)
  reg        err_b_q;          // default slave B pending

  wire [1:0] aw_dec = decode(s_awaddr_i[31:14]);
  wire [1:0] w_tgt  = w_act_q ? w_tgt_q : aw_dec;
  // W may pass when its address is known: with AW in the same cycle or after
  wire       w_route = w_act_q || s_awvalid_i;

  assign m0_awaddr_o  = s_awaddr_i;
  assign m0_awprot_o  = s_awprot_i;
  assign m0_awvalid_o = s_awvalid_i && !w_act_q && (aw_dec == T_SRAM);
  assign m1_awaddr_o  = s_awaddr_i;
  assign m1_awprot_o  = s_awprot_i;
  assign m1_awvalid_o = s_awvalid_i && !w_act_q && (aw_dec == T_APB);

  assign m0_wdata_o  = s_wdata_i;
  assign m0_wstrb_o  = s_wstrb_i;
  assign m0_wvalid_o = s_wvalid_i && w_route && !w_done_q && (w_tgt == T_SRAM);
  assign m1_wdata_o  = s_wdata_i;
  assign m1_wstrb_o  = s_wstrb_i;
  assign m1_wvalid_o = s_wvalid_i && w_route && !w_done_q && (w_tgt == T_APB);

  assign m0_bready_o = s_bready_i && w_act_q && (w_tgt_q == T_SRAM);
  assign m1_bready_o = s_bready_i && w_act_q && (w_tgt_q == T_APB);

  always @* begin
    // AW ready
    if (w_act_q)                 s_awready_o = 1'b0;
    else if (aw_dec == T_SRAM)   s_awready_o = m0_awready_i;
    else if (aw_dec == T_APB)    s_awready_o = m1_awready_i;
    else                         s_awready_o = 1'b1;
    // W ready
    if (!w_route || w_done_q)    s_wready_o = 1'b0;
    else if (w_tgt == T_SRAM)    s_wready_o = m0_wready_i;
    else if (w_tgt == T_APB)     s_wready_o = m1_wready_i;
    else                         s_wready_o = 1'b1;
    // B
    if (!w_act_q) begin
      s_bvalid_o = 1'b0;
      s_bresp_o  = 2'b00;
    end else if (w_tgt_q == T_SRAM) begin
      s_bvalid_o = m0_bvalid_i;
      s_bresp_o  = m0_bresp_i;
    end else if (w_tgt_q == T_APB) begin
      s_bvalid_o = m1_bvalid_i;
      s_bresp_o  = m1_bresp_i;
    end else begin
      s_bvalid_o = err_b_q;
      s_bresp_o  = RESP_DECERR;
    end
  end

  wire aw_hs = s_awvalid_i && s_awready_o;
  wire w_hs  = s_wvalid_i && s_wready_o;
  wire b_hs  = s_bvalid_o && s_bready_i;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      w_act_q  <= 1'b0;
      w_tgt_q  <= T_SRAM;
      w_done_q <= 1'b0;
      err_b_q  <= 1'b0;
    end else begin
      if (aw_hs) begin
        w_act_q <= 1'b1;
        w_tgt_q <= aw_dec;
      end
      if (w_hs) w_done_q <= 1'b1;
      // Default slave answers once both AW and W were accepted
      if (w_tgt == T_ERR && (w_act_q || aw_hs) && (w_done_q || w_hs) && !err_b_q && !b_hs)
        err_b_q <= 1'b1;
      if (b_hs) begin
        w_act_q  <= 1'b0;
        w_done_q <= 1'b0;
        err_b_q  <= 1'b0;
      end
    end
  end

  // ---------------- read channels ----------------
  reg        r_act_q;          // AR accepted, waiting for R
  reg  [1:0] r_tgt_q;
  reg        err_r_q;          // default slave R pending

  wire [1:0] ar_dec = decode(s_araddr_i[31:14]);

  assign m0_araddr_o  = s_araddr_i;
  assign m0_arprot_o  = s_arprot_i;
  assign m0_arvalid_o = s_arvalid_i && !r_act_q && (ar_dec == T_SRAM);
  assign m1_araddr_o  = s_araddr_i;
  assign m1_arprot_o  = s_arprot_i;
  assign m1_arvalid_o = s_arvalid_i && !r_act_q && (ar_dec == T_APB);

  assign m0_rready_o = s_rready_i && r_act_q && (r_tgt_q == T_SRAM);
  assign m1_rready_o = s_rready_i && r_act_q && (r_tgt_q == T_APB);

  always @* begin
    if (r_act_q)                 s_arready_o = 1'b0;
    else if (ar_dec == T_SRAM)   s_arready_o = m0_arready_i;
    else if (ar_dec == T_APB)    s_arready_o = m1_arready_i;
    else                         s_arready_o = 1'b1;

    if (!r_act_q) begin
      s_rvalid_o = 1'b0;
      s_rdata_o  = 32'd0;
      s_rresp_o  = 2'b00;
    end else if (r_tgt_q == T_SRAM) begin
      s_rvalid_o = m0_rvalid_i;
      s_rdata_o  = m0_rdata_i;
      s_rresp_o  = m0_rresp_i;
    end else if (r_tgt_q == T_APB) begin
      s_rvalid_o = m1_rvalid_i;
      s_rdata_o  = m1_rdata_i;
      s_rresp_o  = m1_rresp_i;
    end else begin
      s_rvalid_o = err_r_q;
      s_rdata_o  = 32'd0;
      s_rresp_o  = RESP_DECERR;
    end
  end

  wire ar_hs = s_arvalid_i && s_arready_o;
  wire r_hs  = s_rvalid_o && s_rready_i;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_act_q <= 1'b0;
      r_tgt_q <= T_SRAM;
      err_r_q <= 1'b0;
    end else begin
      if (ar_hs) begin
        r_act_q <= 1'b1;
        r_tgt_q <= ar_dec;
        err_r_q <= (ar_dec == T_ERR);
      end
      if (r_hs) begin
        r_act_q <= 1'b0;
        err_r_q <= 1'b0;
      end
    end
  end

endmodule
