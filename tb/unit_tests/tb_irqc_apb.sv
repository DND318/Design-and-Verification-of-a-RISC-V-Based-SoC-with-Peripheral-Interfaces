// Directed, self-checking testbench for irqc_apb.
// An independent model (regmap.py IRQC: bit 0 UART, 1 SPI, 2 I2C, 3 GPIO,
// IRQ_ID = lowest set bit of STATUS + 1) predicts every register and
// irq_meip_o for all 16 x 16 pending/enable combinations.
// Checks are grouped by vplan item (doc/vplan, sheet IRQC); the log ends
// with a PASS / FAIL / NOT RUN line per item, then "TEST PASSED" or
// "TEST FAILED" for scripts/check_log.sh.
`timescale 1ns/1ps
module tb_irqc_apb;

  localparam logic [11:0] IRQ_PENDING = 12'h000;
  localparam logic [11:0] IRQ_ENABLE  = 12'h004;
  localparam logic [11:0] IRQ_STATUS  = 12'h008;
  localparam logic [11:0] IRQ_ID      = 12'h00C;

  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic        psel = 1'b0;
  logic        penable = 1'b0;
  logic        pwrite = 1'b0;
  logic [11:0] paddr = 12'h0;
  logic [31:0] pwdata = 32'h0;
  logic [3:0]  pstrb = 4'h0;
  logic [31:0] prdata;
  logic        pready, pslverr;
  logic        irq_uart = 1'b0, irq_spi = 1'b0, irq_i2c = 1'b0, irq_gpio = 1'b0;
  logic        irq_meip;


  always #5 clk = ~clk;

  irqc_apb dut (
    .clk_i(clk), .rst_ni(rst_n),
    .psel_i(psel), .penable_i(penable), .pwrite_i(pwrite), .paddr_i(paddr),
    .pwdata_i(pwdata), .pstrb_i(pstrb), .prdata_o(prdata), .pready_o(pready),
    .pslverr_o(pslverr),
    .irq_uart_i(irq_uart), .irq_spi_i(irq_spi), .irq_i2c_i(irq_i2c), .irq_gpio_i(irq_gpio),
    .irq_meip_o(irq_meip)
  );

  initial begin
    #5_000_000;
    $display("ERROR: timeout");
    $display("TEST FAILED");
    $finish;
  end

`include "apb_common.svh"
`include "vplan/vp_irqc.svh"

  task automatic expect_reg(input logic [11:0] addr, input logic [31:0] exp, input string what);
    logic [31:0] d;
    apb_read(addr, d);
    check(d === exp, $sformatf("%s: read %h = %h, expected %h", what, addr, d, exp));
  endtask

  task automatic set_lines(input logic [3:0] p);
    {irq_gpio, irq_i2c, irq_spi, irq_uart} = p;
  endtask

  // Model: priority bit 0 (UART) highest
  function automatic logic [2:0] model_id(input logic [3:0] st);
    for (int i = 0; i < 4; i++) if (st[i]) return 3'(i + 1);
    return 3'd0;
  endfunction

  task automatic check_all(input logic [3:0] p, input logic [3:0] en, input string what);
    logic [3:0] st = p & en;
    expect_reg(IRQ_PENDING, {28'd0, p},  {what, " PENDING"});
    expect_reg(IRQ_ENABLE,  {28'd0, en}, {what, " ENABLE"});
    expect_reg(IRQ_STATUS,  {28'd0, st}, {what, " STATUS"});
    expect_reg(IRQ_ID,      {29'd0, model_id(st)}, {what, " ID"});
    check(irq_meip === (st != 4'd0), $sformatf("%s irq_meip=%b", what, irq_meip));
  endtask

  initial begin
    logic [3:0] en;
    $display("tb_irqc_apb start");
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    vp_regs();                                     // IRQC-01 .. IRQC-14
    apb_write(IRQ_ENABLE, 32'h0);

    $display("-- extra register checks");
    item("IRQC-02");                               // RO with lines high
    set_lines(4'hF);
    apb_write(IRQ_PENDING, 32'h0);
    expect_reg(IRQ_PENDING, 32'hF, "PENDING not writable");
    set_lines(4'h0);
    item("IRQC-09");
    for (int a = 'h010; a < 'h040; a += 4) begin
      apb_write(12'(a), 32'hFFFF_FFFF);
      expect_reg(12'(a), 32'h0, $sformatf("reserved offset %h", a));
    end
    item("IRQC-14");
    apb_write(IRQ_ENABLE, 32'hF);
    apb_write(IRQ_ENABLE, 32'h0, 4'b1110);
    expect_reg(IRQ_ENABLE, 32'hF, "ENABLE strobe 1110 ignored");
    apb_write(IRQ_ENABLE, 32'h0, 4'b0000);
    expect_reg(IRQ_ENABLE, 32'hF, "ENABLE strobe 0000 ignored");
    apb_write(IRQ_ENABLE, 32'h5, 4'b0001);
    expect_reg(IRQ_ENABLE, 32'h5, "ENABLE strobe 0001");
    apb_write(IRQ_ENABLE, 32'h0);

    $display("-- raw lines");
    item("IRQC-15");
    for (int i = 0; i < 4; i++) begin
      set_lines(4'(1 << i));
      expect_reg(IRQ_PENDING, 32'(1 << i), $sformatf("line %0d alone", i));
    end
    set_lines(4'hF); expect_reg(IRQ_PENDING, 32'hF, "all lines");
    set_lines(4'h0); expect_reg(IRQ_PENDING, 32'h0, "no line");

    $display("-- all pending x enable combinations");
    item("IRQC-16");
    for (int e = 0; e < 16; e++) begin
      en = 4'(e);
      apb_write(IRQ_ENABLE, {28'd0, en});
      for (int p = 0; p < 16; p++) begin
        set_lines(4'(p));
        check_all(4'(p), en, $sformatf("pend=%b en=%b", 4'(p), en));
      end
    end

    $display("-- priority");
    item("IRQC-17");
    for (int e = 0; e < 16; e++) begin
      apb_write(IRQ_ENABLE, 32'(e));
      for (int p = 0; p < 16; p++) begin
        set_lines(4'(p));
        expect_reg(IRQ_ID, {29'd0, model_id(4'(p) & 4'(e))}, $sformatf("ID pend=%b en=%b", 4'(p), 4'(e)));
      end
    end
    apb_write(IRQ_ENABLE, 32'hF);
    set_lines(4'b1111); expect_reg(IRQ_ID, 32'd1, "all pending -> UART");
    set_lines(4'b1110); expect_reg(IRQ_ID, 32'd2, "UART cleared -> SPI");
    set_lines(4'b1100); expect_reg(IRQ_ID, 32'd3, "SPI cleared -> I2C");
    set_lines(4'b1000); expect_reg(IRQ_ID, 32'd4, "I2C cleared -> GPIO");
    set_lines(4'b0000); expect_reg(IRQ_ID, 32'd0, "none");

    $display("-- no state: lines followed directly");
    item("IRQC-18");
    apb_write(IRQ_ENABLE, 32'hF);
    for (int i = 0; i < 4; i++) begin
      @(negedge clk);
      set_lines(4'(1 << i)); #1;
      check(irq_meip === 1'b1, $sformatf("meip high with line %0d", i));
      set_lines(4'h0); #1;
      check(irq_meip === 1'b0, $sformatf("meip low when line %0d drops", i));
      check_all(4'h0, 4'hF, $sformatf("nothing latched after line %0d", i));
    end

    $display("-- enable after pending");
    item("IRQC-19");
    apb_write(IRQ_ENABLE, 32'h0);
    for (int i = 0; i < 4; i++) begin
      set_lines(4'(1 << i)); #1;
      check(irq_meip === 1'b0, $sformatf("line %0d pending, enable 0: meip low", i));
      apb_write(IRQ_ENABLE, 32'(1 << i));
      #1 check(irq_meip === 1'b1, $sformatf("meip high right after enabling line %0d", i));
      apb_write(IRQ_ENABLE, 32'h0);
      #1 check(irq_meip === 1'b0, $sformatf("meip low after disabling line %0d", i));
      set_lines(4'h0);
    end

    $display("-- reset clears ENABLE");
    item("IRQC-03");
    set_lines(4'hF);
    apb_write(IRQ_ENABLE, 32'hF);
    #2 rst_n = 1'b0;
    #1 check(irq_meip === 1'b0, "meip low in reset");
    repeat (2) @(posedge clk);
    #1 rst_n = 1'b1;
    check_all(4'hF, 4'h0, "after reset");
    set_lines(4'h0);

    repeat (2) @(posedge clk);
    vplan_pkg::report(VP_BLOCK, VP_N);
    $finish;
  end

endmodule
