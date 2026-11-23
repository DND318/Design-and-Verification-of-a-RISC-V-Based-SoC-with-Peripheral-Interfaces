`timescale 1ns/1ps
// I2C master (*) with APB4 slave interface (APB slot 2, base 0x1000_2000).
// Registers: CTRL 0x00, PRESCALE 0x04, CMD 0x08, TXDATA 0x0C, RXDATA 0x10,
// STATUS 0x14, IER 0x18, ISR 0x1C (see doc/spec/regmap.py). Byte-level command
// interface on top of i2c_engine; single master, 7-bit addressing, no clock
// stretching, no arbitration. Open-drain pins split into _o (tied 0), _oe, _i;
// SCL/SDA inputs pass a 2-FF synchronizer (reset value 1 = idle bus).
// STATUS.bus_busy is derived from the synchronized lines: set on START
// (SDA falls while SCL high), cleared on STOP (SDA rises while SCL high).
// irq_i2c_o = |(ISR & IER).
module i2c_apb (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire        psel_i,
  input  wire        penable_i,
  input  wire        pwrite_i,
  input  wire [11:0] paddr_i,
  input  wire [31:0] pwdata_i,
  input  wire [3:0]  pstrb_i,
  output reg  [31:0] prdata_o,
  output wire        pready_o,
  output wire        pslverr_o,
  output wire        i2c_scl_o,
  output wire        i2c_scl_oe_o,
  input  wire        i2c_scl_i,
  output wire        i2c_sda_o,
  output wire        i2c_sda_oe_o,
  input  wire        i2c_sda_i,
  output wire        irq_i2c_o
);

  localparam [9:0] W_CTRL     = 10'd0;  // 0x00
  localparam [9:0] W_PRESCALE = 10'd1;  // 0x04
  localparam [9:0] W_CMD      = 10'd2;  // 0x08
  localparam [9:0] W_TXDATA   = 10'd3;  // 0x0C
  localparam [9:0] W_RXDATA   = 10'd4;  // 0x10
  localparam [9:0] W_STATUS   = 10'd5;  // 0x14
  localparam [9:0] W_IER      = 10'd6;  // 0x18
  localparam [9:0] W_ISR      = 10'd7;  // 0x1C

  wire [9:0] word = paddr_i[11:2];
  wire       wr   = psel_i & penable_i & pwrite_i;

  // ---------------------------------------------------------------- registers
  reg        en_q;
  reg [15:0] prescale_q;
  reg [7:0]  txdata_q;
  reg        rx_nack_q;
  reg [1:0]  ier_q;
  reg [1:0]  isr_q, isr_d;
  reg        bus_busy_q;
  reg        sda_prev_q;

  wire       eng_busy;
  wire       eng_done;
  wire       eng_ack_valid;
  wire       eng_ack_nack;
  wire [7:0] eng_rxdata;
  wire       scl_s, sda_s;

  // CMD: start bit 0, stop bit 1, write bit 2, read bit 3, nack bit 4.
  // Ignored while busy, with read and write both set, with no action bit, or when disabled.
  wire cmd_wr    = wr & (word == W_CMD) & pstrb_i[0];
  wire cmd_valid = cmd_wr & en_q & ~eng_busy & ~(pwdata_i[2] & pwdata_i[3]) & (|pwdata_i[3:0]);

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      en_q       <= 1'b0;
      prescale_q <= 16'd124;
      txdata_q   <= 8'd0;
      ier_q      <= 2'd0;
    end else if (wr) begin
      if ((word == W_CTRL) && pstrb_i[0])     en_q             <= pwdata_i[0];
      if ((word == W_PRESCALE) && pstrb_i[0]) prescale_q[7:0]  <= pwdata_i[7:0];
      if ((word == W_PRESCALE) && pstrb_i[1]) prescale_q[15:8] <= pwdata_i[15:8];
      if ((word == W_TXDATA) && pstrb_i[0])   txdata_q         <= pwdata_i[7:0];
      if ((word == W_IER) && pstrb_i[0])      ier_q            <= pwdata_i[1:0];
    end
  end

  // ISR: W1C, hardware set wins over a clear in the same cycle.
  always @* begin
    isr_d = isr_q;
    if (wr && (word == W_ISR) && pstrb_i[0])
      isr_d = isr_q & ~pwdata_i[1:0];
    if (eng_done)
      isr_d[0] = 1'b1;
    if (eng_ack_valid && eng_ack_nack)
      isr_d[1] = 1'b1;
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      isr_q     <= 2'd0;
      rx_nack_q <= 1'b0;
    end else begin
      isr_q <= isr_d;
      if (eng_ack_valid)
        rx_nack_q <= eng_ack_nack;
    end
  end

  // ---------------------------------------------------------------- bus monitor
  sync_2ff #(.WIDTH(1), .RESET_VAL(1)) u_sync_scl (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(i2c_scl_i), .q_o(scl_s)
  );
  sync_2ff #(.WIDTH(1), .RESET_VAL(1)) u_sync_sda (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(i2c_sda_i), .q_o(sda_s)
  );

  wire bus_start = scl_s & sda_prev_q & ~sda_s;
  wire bus_stop  = scl_s & ~sda_prev_q & sda_s;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sda_prev_q <= 1'b1;
      bus_busy_q <= 1'b0;
    end else begin
      sda_prev_q <= sda_s;
      if (bus_start)
        bus_busy_q <= 1'b1;
      else if (bus_stop)
        bus_busy_q <= 1'b0;
    end
  end

  // ---------------------------------------------------------------- engine
  i2c_engine u_engine (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .en_i        (en_q),
    .prescale_i  (prescale_q),
    .cmd_valid_i (cmd_valid),
    .cmd_start_i (pwdata_i[0]),
    .cmd_stop_i  (pwdata_i[1]),
    .cmd_write_i (pwdata_i[2]),
    .cmd_read_i  (pwdata_i[3]),
    .cmd_nack_i  (pwdata_i[4]),
    .txdata_i    (txdata_q),
    .sda_i       (sda_s),
    .busy_o      (eng_busy),
    .done_o      (eng_done),
    .ack_valid_o (eng_ack_valid),
    .ack_nack_o  (eng_ack_nack),
    .rxdata_o    (eng_rxdata),
    .scl_oe_o    (i2c_scl_oe_o),
    .sda_oe_o    (i2c_sda_oe_o)
  );

  // ---------------------------------------------------------------- read mux
  always @* begin
    prdata_o = 32'd0;
    case (word)
      W_CTRL:     prdata_o = {31'd0, en_q};
      W_PRESCALE: prdata_o = {16'd0, prescale_q};
      W_CMD:      prdata_o = 32'd0;
      W_TXDATA:   prdata_o = {24'd0, txdata_q};
      W_RXDATA:   prdata_o = {24'd0, eng_rxdata};
      W_STATUS:   prdata_o = {29'd0, bus_busy_q, rx_nack_q, eng_busy};
      W_IER:      prdata_o = {30'd0, ier_q};
      W_ISR:      prdata_o = {30'd0, isr_q};
      default:    prdata_o = 32'd0;
    endcase
  end

  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;
  assign i2c_scl_o = 1'b0;
  assign i2c_sda_o = 1'b0;
  assign irq_i2c_o = |(isr_q & ier_q);

  wire unused_apb = &{1'b0, paddr_i[1:0], pwdata_i[31:16], pstrb_i[3:2]};

endmodule
