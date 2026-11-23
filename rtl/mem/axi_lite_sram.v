`timescale 1ns/1ps
// AXI4-Lite slave around sram_sp (16 KB by default, 4096 x 32).
// One transaction at a time; a write (AW and W both valid) has priority
// over a read. Read data is returned one cycle after the AR handshake.
// Responses are always OKAY. Address bits above the RAM size are ignored
// (the interconnect only sends addresses inside the SRAM window).
module axi_lite_sram #(
  parameter DEPTH        = 4096,
  parameter AW           = 12,
  parameter INIT_FILE_B0 = "",
  parameter INIT_FILE_B1 = "",
  parameter INIT_FILE_B2 = "",
  parameter INIT_FILE_B3 = ""
) (
  input  wire        clk_i,
  input  wire        rst_ni,

  input  wire [31:0] s_awaddr_i,
  input  wire [2:0]  s_awprot_i,
  input  wire        s_awvalid_i,
  output wire        s_awready_o,
  input  wire [31:0] s_wdata_i,
  input  wire [3:0]  s_wstrb_i,
  input  wire        s_wvalid_i,
  output wire        s_wready_o,
  output wire [1:0]  s_bresp_o,
  output wire        s_bvalid_o,
  input  wire        s_bready_i,
  input  wire [31:0] s_araddr_i,
  input  wire [2:0]  s_arprot_i,
  input  wire        s_arvalid_i,
  output wire        s_arready_o,
  output wire [31:0] s_rdata_o,
  output wire [1:0]  s_rresp_o,
  output wire        s_rvalid_o,
  input  wire        s_rready_i
);

  localparam [1:0] S_IDLE  = 2'd0,
                   S_BRESP = 2'd1,
                   S_RDATA = 2'd2;

  reg [1:0] state_q;

  wire do_wr = (state_q == S_IDLE) && s_awvalid_i && s_wvalid_i;
  wire do_rd = (state_q == S_IDLE) && !do_wr && s_arvalid_i;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (do_wr)      state_q <= S_BRESP;
          else if (do_rd) state_q <= S_RDATA;
        end
        S_BRESP: if (s_bready_i) state_q <= S_IDLE;
        S_RDATA: if (s_rready_i) state_q <= S_IDLE;
        default: state_q <= S_IDLE;
      endcase
    end
  end

  // The RAM output register holds its value while en_i = 0, so read data
  // stays valid until the R handshake.
  sram_sp #(
    .DEPTH        (DEPTH),
    .AW           (AW),
    .INIT_FILE_B0 (INIT_FILE_B0),
    .INIT_FILE_B1 (INIT_FILE_B1),
    .INIT_FILE_B2 (INIT_FILE_B2),
    .INIT_FILE_B3 (INIT_FILE_B3)
  ) u_ram (
    .clk_i   (clk_i),
    .en_i    (do_wr || do_rd),
    .we_i    (do_wr ? s_wstrb_i : 4'b0000),
    .addr_i  (do_wr ? s_awaddr_i[AW+1:2] : s_araddr_i[AW+1:2]),
    .wdata_i (s_wdata_i),
    .rdata_o (s_rdata_o)
  );

  assign s_awready_o = do_wr;
  assign s_wready_o  = do_wr;
  assign s_bvalid_o  = (state_q == S_BRESP);
  assign s_bresp_o   = 2'b00;
  assign s_arready_o = do_rd;
  assign s_rvalid_o  = (state_q == S_RDATA);
  assign s_rresp_o   = 2'b00;

  // Byte offset, bits above the RAM size and PROT are not used
  wire unused_in = &{1'b0, s_awaddr_i[31:AW+2], s_awaddr_i[1:0], s_araddr_i[31:AW+2],
                     s_araddr_i[1:0], s_awprot_i, s_arprot_i};

endmodule
