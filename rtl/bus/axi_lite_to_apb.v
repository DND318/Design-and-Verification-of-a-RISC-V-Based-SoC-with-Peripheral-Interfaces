`timescale 1ns/1ps
module axi_lite_to_apb #(
  parameter [15:0] SLOT_EN = 16'h003F
) (
  input  wire          clk_i,
  input  wire          rst_ni,

  // AXI4-Lite slave
  input  wire [31:0]   s_awaddr_i,
  input  wire [2:0]    s_awprot_i,
  input  wire          s_awvalid_i,
  output wire          s_awready_o,
  input  wire [31:0]   s_wdata_i,
  input  wire [3:0]    s_wstrb_i,
  input  wire          s_wvalid_i,
  output wire          s_wready_o,
  output wire [1:0]    s_bresp_o,
  output wire          s_bvalid_o,
  input  wire          s_bready_i,
  input  wire [31:0]   s_araddr_i,
  input  wire [2:0]    s_arprot_i,
  input  wire          s_arvalid_i,
  output wire          s_arready_o,
  output wire [31:0]   s_rdata_o,
  output wire [1:0]    s_rresp_o,
  output wire          s_rvalid_o,
  input  wire          s_rready_i,

  // APB4 master (shared bus, one PSEL per slot)
  output wire [15:0]   psel_o,
  output wire          penable_o,
  output wire          pwrite_o,
  output wire [11:0]   paddr_o,
  output wire [31:0]   pwdata_o,
  output wire [3:0]    pstrb_o,
  output wire [2:0]    pprot_o,
  input  wire [511:0]  prdata_i,     // slot n at [32*n +: 32]
  input  wire [15:0]   pready_i,
  input  wire [15:0]   pslverr_i
);

  localparam [2:0] S_IDLE   = 3'd0,
                   S_SETUP  = 3'd1,
                   S_ACCESS = 3'd2,
                   S_BRESP  = 3'd3,
                   S_RRESP  = 3'd4;

  localparam [1:0] RESP_OKAY   = 2'b00,
                   RESP_SLVERR = 2'b10;

  reg [2:0]  state_q;
  reg        write_q;
  reg [3:0]  slot_q;
  reg [11:0] addr_q;
  reg [31:0] wdata_q;
  reg [3:0]  strb_q;
  reg [2:0]  prot_q;
  reg [31:0] rdata_q;
  reg        err_q;

  wire start_rd = (state_q == S_IDLE) && s_arvalid_i;
  wire start_wr = (state_q == S_IDLE) && !start_rd && s_awvalid_i && s_wvalid_i;
  wire [3:0] wr_slot = s_awaddr_i[15:12];
  wire [3:0] rd_slot = s_araddr_i[15:12];

  wire        cur_ready  = pready_i[slot_q];
  wire        cur_slverr = pslverr_i[slot_q];
  wire [31:0] cur_rdata  = prdata_i[32*slot_q +: 32];

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
      write_q <= 1'b0;
      slot_q  <= 4'd0;
      addr_q  <= 12'd0;
      wdata_q <= 32'd0;
      strb_q  <= 4'd0;
      prot_q  <= 3'd0;
      rdata_q <= 32'd0;
      err_q   <= 1'b0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (start_wr) begin
            write_q <= 1'b1;
            slot_q  <= wr_slot;
            addr_q  <= s_awaddr_i[11:0];
            wdata_q <= s_wdata_i;
            strb_q  <= s_wstrb_i;
            prot_q  <= s_awprot_i;
            err_q   <= !SLOT_EN[wr_slot];
            state_q <= SLOT_EN[wr_slot] ? S_SETUP : S_BRESP;
          end else if (start_rd) begin
            write_q <= 1'b0;
            slot_q  <= rd_slot;
            addr_q  <= s_araddr_i[11:0];
            wdata_q <= 32'd0;
            strb_q  <= 4'd0;
            prot_q  <= s_arprot_i;
            rdata_q <= 32'd0;
            err_q   <= !SLOT_EN[rd_slot];
            state_q <= SLOT_EN[rd_slot] ? S_SETUP : S_RRESP;
          end
        end
        S_SETUP: state_q <= S_ACCESS;
        S_ACCESS: begin
          if (cur_ready) begin
            err_q   <= cur_slverr;
            rdata_q <= write_q ? 32'd0 : cur_rdata;
            state_q <= write_q ? S_BRESP : S_RRESP;
          end
        end
        S_BRESP: if (s_bready_i) state_q <= S_IDLE;
        S_RRESP: if (s_rready_i) state_q <= S_IDLE;
        default: state_q <= S_IDLE;
      endcase
    end
  end

  assign s_awready_o = start_wr;
  assign s_wready_o  = start_wr;
  assign s_arready_o = start_rd;
  assign s_bvalid_o  = (state_q == S_BRESP);
  assign s_bresp_o   = err_q ? RESP_SLVERR : RESP_OKAY;
  assign s_rvalid_o  = (state_q == S_RRESP);
  assign s_rresp_o   = err_q ? RESP_SLVERR : RESP_OKAY;
  assign s_rdata_o   = rdata_q;

  wire apb_active = (state_q == S_SETUP) || (state_q == S_ACCESS);

  assign psel_o    = apb_active ? (16'd1 << slot_q) : 16'd0;
  assign penable_o = (state_q == S_ACCESS);
  assign pwrite_o  = write_q;
  assign paddr_o   = addr_q;
  assign pwdata_o  = wdata_q;
  assign pstrb_o   = strb_q;
  assign pprot_o   = prot_q;

  // The interconnect only routes 0x1000_xxxx here; upper bits are fixed
  wire unused_addr = &{1'b0, s_awaddr_i[31:16], s_araddr_i[31:16]};

endmodule
