`timescale 1ns/1ps
module rv32_lsu (
  input  wire [2:0]  funct3_i,
  input  wire [1:0]  addr_lsb_i,    // byte offset of the address
  input  wire [31:0] store_data_i,
  input  wire [31:0] mem_rdata_i,
  output reg  [31:0] mem_wdata_o,
  output reg  [3:0]  mem_wstrb_o,
  output reg  [31:0] load_data_o,
  output reg         misaligned_o
);

  reg [7:0]  byte_sel;
  reg [15:0] half_sel;

  always @* begin
    case (funct3_i[1:0])
      2'b00:   misaligned_o = 1'b0;
      2'b01:   misaligned_o = addr_lsb_i[0];
      default: misaligned_o = (addr_lsb_i != 2'b00);
    endcase
  end

  // Store: replicate the data on every lane, the strobe selects the lanes
  always @* begin
    case (funct3_i[1:0])
      2'b00: begin
        mem_wdata_o = {4{store_data_i[7:0]}};
        mem_wstrb_o = 4'b0001 << addr_lsb_i;
      end
      2'b01: begin
        mem_wdata_o = {2{store_data_i[15:0]}};
        mem_wstrb_o = addr_lsb_i[1] ? 4'b1100 : 4'b0011;
      end
      default: begin
        mem_wdata_o = store_data_i;
        mem_wstrb_o = 4'b1111;
      end
    endcase
  end

  // Load
  always @* begin
    case (addr_lsb_i)
      2'd0:    byte_sel = mem_rdata_i[7:0];
      2'd1:    byte_sel = mem_rdata_i[15:8];
      2'd2:    byte_sel = mem_rdata_i[23:16];
      default: byte_sel = mem_rdata_i[31:24];
    endcase
    half_sel = addr_lsb_i[1] ? mem_rdata_i[31:16] : mem_rdata_i[15:0];

    case (funct3_i)
      3'b000:  load_data_o = {{24{byte_sel[7]}}, byte_sel};   // LB
      3'b001:  load_data_o = {{16{half_sel[15]}}, half_sel};  // LH
      3'b100:  load_data_o = {24'b0, byte_sel};               // LBU
      3'b101:  load_data_o = {16'b0, half_sel};               // LHU
      default: load_data_o = mem_rdata_i;                     // LW
    endcase
  end

endmodule
