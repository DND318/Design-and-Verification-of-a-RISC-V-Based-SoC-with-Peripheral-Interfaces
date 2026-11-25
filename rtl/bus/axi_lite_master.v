`timescale 1ns/1ps
module axi_lite_master (
  input  wire        clk_i,
  input  wire        rst_ni,

  // CPU memory port (cpu_wrapper)
  input  wire        mem_req_i,
  input  wire        mem_instr_i,
  input  wire        mem_we_i,
  input  wire [3:0]  mem_wstrb_i,
  input  wire [31:0] mem_addr_i,
  input  wire [31:0] mem_wdata_i,
  output wire [31:0] mem_rdata_o,
  output wire        mem_ready_o,
  output wire        mem_err_o,

  // AXI4-Lite master
  output wire [31:0] m_awaddr_o,
  output wire [2:0]  m_awprot_o,
  output wire        m_awvalid_o,
  input  wire        m_awready_i,
  output wire [31:0] m_wdata_o,
  output wire [3:0]  m_wstrb_o,
  output wire        m_wvalid_o,
  input  wire        m_wready_i,
  input  wire [1:0]  m_bresp_i,
  input  wire        m_bvalid_i,
  output wire        m_bready_o,
  output wire [31:0] m_araddr_o,
  output wire [2:0]  m_arprot_o,
  output wire        m_arvalid_o,
  input  wire        m_arready_i,
  input  wire [31:0] m_rdata_i,
  input  wire [1:0]  m_rresp_i,
  input  wire        m_rvalid_i,
  output wire        m_rready_o
);

  localparam [1:0] S_IDLE = 2'd0,
                   S_RD   = 2'd1,
                   S_WR   = 2'd2;

  reg [1:0] state_q;
  reg       aw_pend_q, w_pend_q, ar_pend_q;

  wire [2:0] prot = {mem_instr_i, 1'b0, 1'b1};

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= S_IDLE;
      aw_pend_q <= 1'b0;
      w_pend_q  <= 1'b0;
      ar_pend_q <= 1'b0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (mem_req_i) begin
            if (mem_we_i) begin
              aw_pend_q <= 1'b1;
              w_pend_q  <= 1'b1;
              state_q   <= S_WR;
            end else begin
              ar_pend_q <= 1'b1;
              state_q   <= S_RD;
            end
          end
        end
        S_RD: begin
          if (ar_pend_q && m_arready_i) ar_pend_q <= 1'b0;
          if (m_rvalid_i)               state_q   <= S_IDLE;
        end
        S_WR: begin
          if (aw_pend_q && m_awready_i) aw_pend_q <= 1'b0;
          if (w_pend_q && m_wready_i)   w_pend_q  <= 1'b0;
          if (m_bvalid_i)               state_q   <= S_IDLE;
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end

  // Address, data and strobes come straight from the CPU port, which holds
  // them stable until mem_ready_o.
  assign m_awaddr_o  = mem_addr_i;
  assign m_awprot_o  = prot;
  assign m_awvalid_o = aw_pend_q;
  assign m_wdata_o   = mem_wdata_i;
  assign m_wstrb_o   = mem_wstrb_i;
  assign m_wvalid_o  = w_pend_q;
  assign m_bready_o  = (state_q == S_WR);
  assign m_araddr_o  = mem_addr_i;
  assign m_arprot_o  = prot;
  assign m_arvalid_o = ar_pend_q;
  assign m_rready_o  = (state_q == S_RD);

  assign mem_ready_o = ((state_q == S_RD) && m_rvalid_i) || ((state_q == S_WR) && m_bvalid_i);
  assign mem_rdata_o = m_rdata_i;
  assign mem_err_o   = (state_q == S_RD) ? m_rresp_i[1] : m_bresp_i[1];

  // Only RESP[1] (SLVERR/DECERR) matters; RESP[0] is not needed
  wire unused_resp = &{1'b0, m_bresp_i[0], m_rresp_i[0]};

endmodule
