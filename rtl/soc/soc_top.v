`timescale 1ns/1ps
// RISC-V SoC top level (doc/spec): RV32IM core -> AXI4-Lite master adapter
// -> 1x2 interconnect -> {16 KB SRAM at 0x0000_0000, AXI4-Lite to APB4
// bridge at 0x1000_0000} -> APB slaves UART (slot 0), SPI (1), I2C (2),
// Timer (3), IRQ controller (4), GPIO (5).
// HAS_* = 0 leaves an extension block out; its window then answers SLVERR
// and its interrupt is 0. rst_ni is the raw external reset; it is
// synchronized here (async assert, sync release).
module soc_top #(
  parameter       INIT_FILE_B0 = "",
  parameter       INIT_FILE_B1 = "",
  parameter       INIT_FILE_B2 = "",
  parameter       INIT_FILE_B3 = "",
  parameter [0:0] HAS_I2C      = 1'b1,
  parameter [0:0] HAS_TIMER    = 1'b1,
  parameter [0:0] HAS_IRQC     = 1'b1,
  parameter [0:0] HAS_GPIO     = 1'b1
) (
  input  wire       clk_i,
  input  wire       rst_ni,

  output wire       uart_tx_o,
  input  wire       uart_rx_i,

  output wire       spi_sclk_o,
  output wire       spi_mosi_o,
  input  wire       spi_miso_i,
  output wire       spi_cs_no,

  output wire       i2c_scl_o,
  output wire       i2c_scl_oe_o,
  input  wire       i2c_scl_i,
  output wire       i2c_sda_o,
  output wire       i2c_sda_oe_o,
  input  wire       i2c_sda_i,

  output wire [7:0] gpio_o,
  output wire [7:0] gpio_oe_o,
  input  wire [7:0] gpio_i
);

  localparam [15:0] SLOT_EN = {10'd0, HAS_GPIO, HAS_IRQC, HAS_TIMER, HAS_I2C, 1'b1, 1'b1};

  // ---------------- reset ----------------
  wire rst_n;

  rst_sync u_rst_sync (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .rst_no (rst_n)
  );

  // ---------------- CPU ----------------
  wire        mem_req, mem_instr, mem_we, mem_ready, mem_err;
  wire [3:0]  mem_wstrb;
  wire [31:0] mem_addr, mem_wdata, mem_rdata;
  wire        irq_mtip, irq_meip;

  cpu_wrapper u_cpu (
    .clk_i       (clk_i),
    .rst_ni      (rst_n),
    .mem_req_o   (mem_req),
    .mem_instr_o (mem_instr),
    .mem_we_o    (mem_we),
    .mem_wstrb_o (mem_wstrb),
    .mem_addr_o  (mem_addr),
    .mem_wdata_o (mem_wdata),
    .mem_rdata_i (mem_rdata),
    .mem_ready_i (mem_ready),
    .mem_err_i   (mem_err),
    .irq_mtip_i  (irq_mtip),
    .irq_meip_i  (irq_meip)
  );

  // ---------------- AXI4-Lite ----------------
  // m_*: master adapter -> interconnect, s0_*: -> SRAM, s1_*: -> APB bridge
  wire [31:0] m_awaddr,  s0_awaddr,  s1_awaddr;
  wire [2:0]  m_awprot,  s0_awprot,  s1_awprot;
  wire        m_awvalid, s0_awvalid, s1_awvalid;
  wire        m_awready, s0_awready, s1_awready;
  wire [31:0] m_wdata,   s0_wdata,   s1_wdata;
  wire [3:0]  m_wstrb,   s0_wstrb,   s1_wstrb;
  wire        m_wvalid,  s0_wvalid,  s1_wvalid;
  wire        m_wready,  s0_wready,  s1_wready;
  wire [1:0]  m_bresp,   s0_bresp,   s1_bresp;
  wire        m_bvalid,  s0_bvalid,  s1_bvalid;
  wire        m_bready,  s0_bready,  s1_bready;
  wire [31:0] m_araddr,  s0_araddr,  s1_araddr;
  wire [2:0]  m_arprot,  s0_arprot,  s1_arprot;
  wire        m_arvalid, s0_arvalid, s1_arvalid;
  wire        m_arready, s0_arready, s1_arready;
  wire [31:0] m_rdata,   s0_rdata,   s1_rdata;
  wire [1:0]  m_rresp,   s0_rresp,   s1_rresp;
  wire        m_rvalid,  s0_rvalid,  s1_rvalid;
  wire        m_rready,  s0_rready,  s1_rready;

  axi_lite_master u_axi_master (
    .clk_i       (clk_i),
    .rst_ni      (rst_n),
    .mem_req_i   (mem_req),
    .mem_instr_i (mem_instr),
    .mem_we_i    (mem_we),
    .mem_wstrb_i (mem_wstrb),
    .mem_addr_i  (mem_addr),
    .mem_wdata_i (mem_wdata),
    .mem_rdata_o (mem_rdata),
    .mem_ready_o (mem_ready),
    .mem_err_o   (mem_err),
    .m_awaddr_o  (m_awaddr),
    .m_awprot_o  (m_awprot),
    .m_awvalid_o (m_awvalid),
    .m_awready_i (m_awready),
    .m_wdata_o   (m_wdata),
    .m_wstrb_o   (m_wstrb),
    .m_wvalid_o  (m_wvalid),
    .m_wready_i  (m_wready),
    .m_bresp_i   (m_bresp),
    .m_bvalid_i  (m_bvalid),
    .m_bready_o  (m_bready),
    .m_araddr_o  (m_araddr),
    .m_arprot_o  (m_arprot),
    .m_arvalid_o (m_arvalid),
    .m_arready_i (m_arready),
    .m_rdata_i   (m_rdata),
    .m_rresp_i   (m_rresp),
    .m_rvalid_i  (m_rvalid),
    .m_rready_o  (m_rready)
  );

  axi_lite_xbar_1x2 u_xbar (
    .clk_i        (clk_i),
    .rst_ni       (rst_n),
    .s_awaddr_i   (m_awaddr),
    .s_awprot_i   (m_awprot),
    .s_awvalid_i  (m_awvalid),
    .s_awready_o  (m_awready),
    .s_wdata_i    (m_wdata),
    .s_wstrb_i    (m_wstrb),
    .s_wvalid_i   (m_wvalid),
    .s_wready_o   (m_wready),
    .s_bresp_o    (m_bresp),
    .s_bvalid_o   (m_bvalid),
    .s_bready_i   (m_bready),
    .s_araddr_i   (m_araddr),
    .s_arprot_i   (m_arprot),
    .s_arvalid_i  (m_arvalid),
    .s_arready_o  (m_arready),
    .s_rdata_o    (m_rdata),
    .s_rresp_o    (m_rresp),
    .s_rvalid_o   (m_rvalid),
    .s_rready_i   (m_rready),
    .m0_awaddr_o  (s0_awaddr),
    .m0_awprot_o  (s0_awprot),
    .m0_awvalid_o (s0_awvalid),
    .m0_awready_i (s0_awready),
    .m0_wdata_o   (s0_wdata),
    .m0_wstrb_o   (s0_wstrb),
    .m0_wvalid_o  (s0_wvalid),
    .m0_wready_i  (s0_wready),
    .m0_bresp_i   (s0_bresp),
    .m0_bvalid_i  (s0_bvalid),
    .m0_bready_o  (s0_bready),
    .m0_araddr_o  (s0_araddr),
    .m0_arprot_o  (s0_arprot),
    .m0_arvalid_o (s0_arvalid),
    .m0_arready_i (s0_arready),
    .m0_rdata_i   (s0_rdata),
    .m0_rresp_i   (s0_rresp),
    .m0_rvalid_i  (s0_rvalid),
    .m0_rready_o  (s0_rready),
    .m1_awaddr_o  (s1_awaddr),
    .m1_awprot_o  (s1_awprot),
    .m1_awvalid_o (s1_awvalid),
    .m1_awready_i (s1_awready),
    .m1_wdata_o   (s1_wdata),
    .m1_wstrb_o   (s1_wstrb),
    .m1_wvalid_o  (s1_wvalid),
    .m1_wready_i  (s1_wready),
    .m1_bresp_i   (s1_bresp),
    .m1_bvalid_i  (s1_bvalid),
    .m1_bready_o  (s1_bready),
    .m1_araddr_o  (s1_araddr),
    .m1_arprot_o  (s1_arprot),
    .m1_arvalid_o (s1_arvalid),
    .m1_arready_i (s1_arready),
    .m1_rdata_i   (s1_rdata),
    .m1_rresp_i   (s1_rresp),
    .m1_rvalid_i  (s1_rvalid),
    .m1_rready_o  (s1_rready)
  );

  axi_lite_sram #(
    .DEPTH        (4096),
    .AW           (12),
    .INIT_FILE_B0 (INIT_FILE_B0),
    .INIT_FILE_B1 (INIT_FILE_B1),
    .INIT_FILE_B2 (INIT_FILE_B2),
    .INIT_FILE_B3 (INIT_FILE_B3)
  ) u_sram (
    .clk_i       (clk_i),
    .rst_ni      (rst_n),
    .s_awaddr_i  (s0_awaddr),
    .s_awprot_i  (s0_awprot),
    .s_awvalid_i (s0_awvalid),
    .s_awready_o (s0_awready),
    .s_wdata_i   (s0_wdata),
    .s_wstrb_i   (s0_wstrb),
    .s_wvalid_i  (s0_wvalid),
    .s_wready_o  (s0_wready),
    .s_bresp_o   (s0_bresp),
    .s_bvalid_o  (s0_bvalid),
    .s_bready_i  (s0_bready),
    .s_araddr_i  (s0_araddr),
    .s_arprot_i  (s0_arprot),
    .s_arvalid_i (s0_arvalid),
    .s_arready_o (s0_arready),
    .s_rdata_o   (s0_rdata),
    .s_rresp_o   (s0_rresp),
    .s_rvalid_o  (s0_rvalid),
    .s_rready_i  (s0_rready)
  );

  // ---------------- APB ----------------
  wire [15:0]  psel;
  wire         penable, pwrite;
  wire [11:0]  paddr;
  wire [31:0]  pwdata;
  wire [3:0]   pstrb;
  wire [2:0]   pprot;
  wire [511:0] prdata;
  wire [15:0]  pready, pslverr;

  axi_lite_to_apb #(
    .SLOT_EN (SLOT_EN)
  ) u_apb_bridge (
    .clk_i       (clk_i),
    .rst_ni      (rst_n),
    .s_awaddr_i  (s1_awaddr),
    .s_awprot_i  (s1_awprot),
    .s_awvalid_i (s1_awvalid),
    .s_awready_o (s1_awready),
    .s_wdata_i   (s1_wdata),
    .s_wstrb_i   (s1_wstrb),
    .s_wvalid_i  (s1_wvalid),
    .s_wready_o  (s1_wready),
    .s_bresp_o   (s1_bresp),
    .s_bvalid_o  (s1_bvalid),
    .s_bready_i  (s1_bready),
    .s_araddr_i  (s1_araddr),
    .s_arprot_i  (s1_arprot),
    .s_arvalid_i (s1_arvalid),
    .s_arready_o (s1_arready),
    .s_rdata_o   (s1_rdata),
    .s_rresp_o   (s1_rresp),
    .s_rvalid_o  (s1_rvalid),
    .s_rready_i  (s1_rready),
    .psel_o      (psel),
    .penable_o   (penable),
    .pwrite_o    (pwrite),
    .paddr_o     (paddr),
    .pwdata_o    (pwdata),
    .pstrb_o     (pstrb),
    .pprot_o     (pprot),
    .prdata_i    (prdata),
    .pready_i    (pready),
    .pslverr_i   (pslverr)
  );

  // Slots 6..15 are reserved: the bridge never selects them
  assign prdata[511:192] = 320'd0;
  assign pready[15:6]    = 10'h3FF;
  assign pslverr[15:6]   = 10'd0;

  wire irq_uart, irq_spi, irq_i2c, irq_gpio;

  // Slot 0: UART
  uart_apb u_uart (
    .clk_i      (clk_i),
    .rst_ni     (rst_n),
    .psel_i     (psel[0]),
    .penable_i  (penable),
    .pwrite_i   (pwrite),
    .paddr_i    (paddr),
    .pwdata_i   (pwdata),
    .pstrb_i    (pstrb),
    .prdata_o   (prdata[31:0]),
    .pready_o   (pready[0]),
    .pslverr_o  (pslverr[0]),
    .uart_tx_o  (uart_tx_o),
    .uart_rx_i  (uart_rx_i),
    .irq_uart_o (irq_uart)
  );

  // Slot 1: SPI
  spi_apb u_spi (
    .clk_i      (clk_i),
    .rst_ni     (rst_n),
    .psel_i     (psel[1]),
    .penable_i  (penable),
    .pwrite_i   (pwrite),
    .paddr_i    (paddr),
    .pwdata_i   (pwdata),
    .pstrb_i    (pstrb),
    .prdata_o   (prdata[63:32]),
    .pready_o   (pready[1]),
    .pslverr_o  (pslverr[1]),
    .spi_sclk_o (spi_sclk_o),
    .spi_mosi_o (spi_mosi_o),
    .spi_miso_i (spi_miso_i),
    .spi_cs_no  (spi_cs_no),
    .irq_spi_o  (irq_spi)
  );

  // Slot 2: I2C (*)
  generate
    if (HAS_I2C) begin : g_i2c
      i2c_apb u_i2c (
        .clk_i        (clk_i),
        .rst_ni       (rst_n),
        .psel_i       (psel[2]),
        .penable_i    (penable),
        .pwrite_i     (pwrite),
        .paddr_i      (paddr),
        .pwdata_i     (pwdata),
        .pstrb_i      (pstrb),
        .prdata_o     (prdata[95:64]),
        .pready_o     (pready[2]),
        .pslverr_o    (pslverr[2]),
        .i2c_scl_o    (i2c_scl_o),
        .i2c_scl_oe_o (i2c_scl_oe_o),
        .i2c_scl_i    (i2c_scl_i),
        .i2c_sda_o    (i2c_sda_o),
        .i2c_sda_oe_o (i2c_sda_oe_o),
        .i2c_sda_i    (i2c_sda_i),
        .irq_i2c_o    (irq_i2c)
      );
    end else begin : g_no_i2c
      assign prdata[95:64] = 32'd0;
      assign pready[2]     = 1'b1;
      assign pslverr[2]    = 1'b0;
      assign i2c_scl_o     = 1'b0;
      assign i2c_scl_oe_o  = 1'b0;
      assign i2c_sda_o     = 1'b0;
      assign i2c_sda_oe_o  = 1'b0;
      assign irq_i2c       = 1'b0;
      wire unused_i2c = &{1'b0, i2c_scl_i, i2c_sda_i};
    end
  endgenerate

  // Slot 3: Timer (*)
  generate
    if (HAS_TIMER) begin : g_timer
      timer_apb u_timer (
        .clk_i      (clk_i),
        .rst_ni     (rst_n),
        .psel_i     (psel[3]),
        .penable_i  (penable),
        .pwrite_i   (pwrite),
        .paddr_i    (paddr),
        .pwdata_i   (pwdata),
        .pstrb_i    (pstrb),
        .prdata_o   (prdata[127:96]),
        .pready_o   (pready[3]),
        .pslverr_o  (pslverr[3]),
        .irq_mtip_o (irq_mtip)
      );
    end else begin : g_no_timer
      assign prdata[127:96] = 32'd0;
      assign pready[3]      = 1'b1;
      assign pslverr[3]     = 1'b0;
      assign irq_mtip       = 1'b0;
    end
  endgenerate

  // Slot 4: IRQ controller (*)
  generate
    if (HAS_IRQC) begin : g_irqc
      irqc_apb u_irqc (
        .clk_i      (clk_i),
        .rst_ni     (rst_n),
        .psel_i     (psel[4]),
        .penable_i  (penable),
        .pwrite_i   (pwrite),
        .paddr_i    (paddr),
        .pwdata_i   (pwdata),
        .pstrb_i    (pstrb),
        .prdata_o   (prdata[159:128]),
        .pready_o   (pready[4]),
        .pslverr_o  (pslverr[4]),
        .irq_uart_i (irq_uart),
        .irq_spi_i  (irq_spi),
        .irq_i2c_i  (irq_i2c),
        .irq_gpio_i (irq_gpio),
        .irq_meip_o (irq_meip)
      );
    end else begin : g_no_irqc
      assign prdata[159:128] = 32'd0;
      assign pready[4]       = 1'b1;
      assign pslverr[4]      = 1'b0;
      assign irq_meip        = 1'b0;
      wire unused_irq = &{1'b0, irq_uart, irq_spi, irq_i2c, irq_gpio};
    end
  endgenerate

  // Slot 5: GPIO
  generate
    if (HAS_GPIO) begin : g_gpio
      gpio_apb u_gpio (
        .clk_i      (clk_i),
        .rst_ni     (rst_n),
        .psel_i     (psel[5]),
        .penable_i  (penable),
        .pwrite_i   (pwrite),
        .paddr_i    (paddr),
        .pwdata_i   (pwdata),
        .pstrb_i    (pstrb),
        .prdata_o   (prdata[191:160]),
        .pready_o   (pready[5]),
        .pslverr_o  (pslverr[5]),
        .gpio_o     (gpio_o),
        .gpio_oe_o  (gpio_oe_o),
        .gpio_i     (gpio_i),
        .irq_gpio_o (irq_gpio)
      );
    end else begin : g_no_gpio
      assign prdata[191:160] = 32'd0;
      assign pready[5]       = 1'b1;
      assign pslverr[5]      = 1'b0;
      assign gpio_o          = 8'd0;
      assign gpio_oe_o       = 8'd0;
      assign irq_gpio        = 1'b0;
      wire unused_gpio = &{1'b0, gpio_i};
    end
  endgenerate

  // pprot is not used by the peripherals; psel[15:6] are free slots, and
  // psel[5:2] are unused when a HAS_* parameter is 0
  wire unused_apb = &{1'b0, pprot, psel[15:2]};

endmodule
