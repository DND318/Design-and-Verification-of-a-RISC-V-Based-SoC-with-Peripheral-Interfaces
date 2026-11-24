// Directed, self-checking testbench for gpio_apb.
// Expected values come from regmap.py GPIO and the spec: GPIO_IN is gpio_i
// after a 2-FF synchronizer, GPIO_IS is W1C and is set by a rising edge of the
// synchronized input when GPIO_IE is 1, irq_gpio_o = |(GPIO_IS & GPIO_IE).
// Checks are grouped by vplan item (doc/vplan, sheet GPIO); the log ends
// with a PASS / FAIL / NOT RUN line per item, then "TEST PASSED" or
// "TEST FAILED" for scripts/check_log.sh.
`timescale 1ns/1ps
module tb_gpio_apb;

  localparam logic [11:0] GPIO_OUT = 12'h000;
  localparam logic [11:0] GPIO_OE  = 12'h004;
  localparam logic [11:0] GPIO_IN  = 12'h008;
  localparam logic [11:0] GPIO_IE  = 12'h00C;
  localparam logic [11:0] GPIO_IS  = 12'h010;

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
  logic [7:0]  gpio_o, gpio_oe;
  logic [7:0]  gpio_i = 8'h00;
  logic        irq_gpio;

  int          edge_lat = 3;   // measured: rising edges from a gpio_i change to GPIO_IS set

  always #5 clk = ~clk;

  gpio_apb dut (
    .clk_i(clk), .rst_ni(rst_n),
    .psel_i(psel), .penable_i(penable), .pwrite_i(pwrite), .paddr_i(paddr),
    .pwdata_i(pwdata), .pstrb_i(pstrb), .prdata_o(prdata), .pready_o(pready),
    .pslverr_o(pslverr),
    .gpio_o(gpio_o), .gpio_oe_o(gpio_oe), .gpio_i(gpio_i), .irq_gpio_o(irq_gpio)
  );

  initial begin
    #5_000_000;
    $display("ERROR: timeout");
    $display("TEST FAILED");
    $finish;
  end

`include "apb_common.svh"
`include "vplan/vp_gpio.svh"

  task automatic expect_reg(input logic [11:0] addr, input logic [31:0] exp, input string what);
    logic [31:0] d;
    apb_read(addr, d);
    check(d === exp, $sformatf("%s: read %h = %h, expected %h", what, addr, d, exp));
  endtask

  task automatic idle(input int n);
    repeat (n) @(posedge clk);
    #1;
  endtask

  // Change the pins and wait until the synchronizer and edge detector settled.
  task automatic pins(input logic [7:0] v);
    gpio_i = v;
    idle(4);
  endtask

  task automatic test_reset_values();
    $display("-- reset values");
    expect_reg(GPIO_OUT, 32'h0, "GPIO_OUT reset");
    expect_reg(GPIO_OE,  32'h0, "GPIO_OE reset");
    expect_reg(GPIO_IN,  {24'h0, gpio_i}, "GPIO_IN reset");
    expect_reg(GPIO_IE,  32'h0, "GPIO_IE reset");
    expect_reg(GPIO_IS,  32'h0, "GPIO_IS reset");
    check(gpio_o === 8'h00 && gpio_oe === 8'h00, $sformatf("pins after reset o=%h oe=%h", gpio_o, gpio_oe));
    check(irq_gpio === 1'b0, "irq_gpio after reset");
  endtask

  task automatic test_rw_regs();
    logic [11:0] regs [3] = '{GPIO_OUT, GPIO_OE, GPIO_IE};
    $display("-- GPIO_OUT / GPIO_OE / GPIO_IE read/write, strobes, pins");
    foreach (regs[i]) begin
      apb_write(regs[i], 32'hFFFF_FFFF);
      expect_reg(regs[i], 32'h0000_00FF, $sformatf("reg %h reserved bits", regs[i]));
      apb_write(regs[i], 32'h0000_005A);
      expect_reg(regs[i], 32'h0000_005A, $sformatf("reg %h = 5A", regs[i]));
      apb_write(regs[i], 32'h0000_00C3, 4'b1110);
      expect_reg(regs[i], 32'h0000_005A, $sformatf("reg %h strobe 1110 ignored", regs[i]));
      apb_write(regs[i], 32'h0000_00C3, 4'b0000);
      expect_reg(regs[i], 32'h0000_005A, $sformatf("reg %h strobe 0000 ignored", regs[i]));
      apb_write(regs[i], 32'hFFFF_FFC3, 4'b0001);
      expect_reg(regs[i], 32'h0000_00C3, $sformatf("reg %h strobe 0001", regs[i]));
    end
    // Pin outputs follow the registers
    item("GPIO-16");
    for (int v = 0; v < 256; v += 37) begin
      apb_write(GPIO_OUT, v);
      apb_write(GPIO_OE, {24'h0, 8'(v) ^ 8'hFF});
      check(gpio_o === 8'(v), $sformatf("gpio_o=%h expected %h", gpio_o, 8'(v)));
      check(gpio_oe === (8'(v) ^ 8'hFF), $sformatf("gpio_oe=%h expected %h", gpio_oe, 8'(v) ^ 8'hFF));
    end
    // Outputs do not loop back into GPIO_IN
    gpio_i = 8'h00;
    apb_write(GPIO_OUT, 32'hFF);
    apb_write(GPIO_OE,  32'hFF);
    idle(3);
    expect_reg(GPIO_IN, 32'h0, "GPIO_IN independent of GPIO_OUT");
    apb_write(GPIO_OUT, 32'h0);
    apb_write(GPIO_OE,  32'h0);
    apb_write(GPIO_IE,  32'h0);
    // Reserved offsets
    item("GPIO-10");
    for (int a = 'h014; a < 'h040; a += 4) begin
      apb_write(12'(a), 32'hFFFF_FFFF);
      expect_reg(12'(a), 32'h0, $sformatf("reserved offset %h", a));
    end
    apb_write(12'hFFC, 32'hFFFF_FFFF);
    expect_reg(12'hFFC, 32'h0, "reserved offset FFC");
    expect_reg(GPIO_OUT, 32'h0, "GPIO_OUT after reserved writes");
    expect_reg(GPIO_IE,  32'h0, "GPIO_IE after reserved writes");
    apb_write(GPIO_OUT, 32'h3C);
    expect_reg(GPIO_OUT | 12'h1, 32'h3C, "GPIO_OUT at unaligned 0x01");
    apb_write(GPIO_OUT, 32'h0);
  endtask

  task automatic test_input();
    logic [31:0] d;
    logic [7:0]  pat [6] = '{8'h00, 8'hFF, 8'hA5, 8'h5A, 8'h01, 8'h80};
    $display("-- GPIO_IN");
    item("GPIO-17");
    foreach (pat[i]) begin
      pins(pat[i]);
      expect_reg(GPIO_IN, {24'h0, pat[i]}, $sformatf("GPIO_IN pattern %h", pat[i]));
    end
    item("GPIO-06");
    apb_write(GPIO_IN, 32'h0000_0000);
    expect_reg(GPIO_IN, 32'h0000_0080, "GPIO_IN is read-only");
    item("GPIO-18");
    // Synchronizer latency: a change at the start of the SETUP cycle of a read
    // is not visible in its ACCESS cycle (2 flip-flops), but in the next read.
    pins(8'h00);
    fork
      apb_read(GPIO_IN, d);
      begin @(posedge clk); #1; gpio_i = 8'hC3; end
    join
    check(d === 32'h0, $sformatf("GPIO_IN visible after 1 clock (%h): not 2-FF synchronized", d));
    expect_reg(GPIO_IN, 32'hC3, "GPIO_IN after 2 clocks");
    pins(8'h00);
  endtask

  task automatic test_edges();
    int n;
    $display("-- edge detection");
    item("GPIO-18");
    pins(8'h00);
    apb_write(GPIO_IE, 32'hFF);
    // Measure latency: gpio_i change just after edge E0 -> irq after edge E0+n
    gpio_i = 8'h01;
    n = 0;
    for (int k = 1; k <= 8 && n == 0; k++) begin
      @(posedge clk); #1;
      if (irq_gpio === 1'b1) n = k;
    end
    check(n >= 3, $sformatf("edge latency %0d clocks, expected >= 3 (2-FF + status flop)", n));
    check(n == 3, $sformatf("edge latency %0d clocks, design value 3", n));
    if (n != 0) edge_lat = n;
    $display("   pin-to-irq latency %0d clocks", edge_lat);
    item("GPIO-19");
    expect_reg(GPIO_IS, 32'h01, "IS after rising edge pin 0");
    apb_write(GPIO_IS, 32'h01);
    expect_reg(GPIO_IS, 32'h00, "IS cleared");
    pins(8'h00);

    // Each pin individually: rising sets, falling does not, W1C clears
    for (int i = 0; i < 8; i++) begin
      pins(8'(1 << i));
      expect_reg(GPIO_IS, 32'(1 << i), $sformatf("IS after rise pin %0d", i));
      check(irq_gpio === 1'b1, $sformatf("irq after rise pin %0d", i));
      pins(8'h00);
      expect_reg(GPIO_IS, 32'(1 << i), $sformatf("IS unchanged by fall pin %0d", i));
      apb_write(GPIO_IS, 32'(1 << i) ^ 32'hFF, 4'b0001);   // other bits: nothing to clear
      expect_reg(GPIO_IS, 32'(1 << i), $sformatf("W1C of other bits keeps pin %0d", i));
      apb_write(GPIO_IS, 32'(1 << i));
      expect_reg(GPIO_IS, 32'h0, $sformatf("W1C pin %0d", i));
      check(irq_gpio === 1'b0, $sformatf("irq low after W1C pin %0d", i));
    end

    // Falling edge and steady level do not set IS
    item("GPIO-20");
    pins(8'hFF);
    apb_write(GPIO_IS, 32'hFF);
    expect_reg(GPIO_IS, 32'h00, "W1C all while pins high");
    idle(10);
    expect_reg(GPIO_IS, 32'h00, "steady High does not set IS");
    pins(8'h00);
    expect_reg(GPIO_IS, 32'h00, "falling edge does not set IS");
    check(irq_gpio === 1'b0, "irq low after falling edges");

    // One-clock pulse is caught
    item("GPIO-19");
    @(posedge clk); #1 gpio_i = 8'h10;
    @(posedge clk); #1 gpio_i = 8'h00;
    idle(4);
    expect_reg(GPIO_IS, 32'h10, "one-clock pulse sets IS");
    apb_write(GPIO_IS, 32'hFF);

    // IE gates setting
    item("GPIO-21");
    apb_write(GPIO_IE, 32'h0F);
    pins(8'hFF);
    expect_reg(GPIO_IS, 32'h0F, "IE=0F: only low nibble set");
    pins(8'h00);
    apb_write(GPIO_IE, 32'hFF);
    expect_reg(GPIO_IS, 32'h0F, "enabling IE later does not set old edges");

    // IE gates the irq output without clearing IS
    item("GPIO-22");
    apb_write(GPIO_IE, 32'h00);
    idle(1);
    check(irq_gpio === 1'b0, "irq low with IE=0, IS=0F");
    expect_reg(GPIO_IS, 32'h0F, "IS kept with IE=0");
    apb_write(GPIO_IE, 32'h10);
    check(irq_gpio === 1'b0, "irq low with IE=10, IS=0F");
    apb_write(GPIO_IE, 32'h04);
    check(irq_gpio === 1'b1, "irq high with IE=04, IS=0F");
    apb_write(GPIO_IS, 32'h04);
    check(irq_gpio === 1'b0, "irq low after W1C bit 2 (IS=0B, IE=04)");
    apb_write(GPIO_IE, 32'hFF);
    check(irq_gpio === 1'b1, "irq high with IE=FF, IS=0B");

    // W1C details
    item("GPIO-23");
    apb_write(GPIO_IS, 32'h00);
    expect_reg(GPIO_IS, 32'h0B, "W1C write 0 no effect");
    apb_write(GPIO_IS, 32'hFFFF_FFFF, 4'b1110);
    expect_reg(GPIO_IS, 32'h0B, "W1C with pstrb[0]=0 no effect");
    apb_write(GPIO_IS, 32'h0000_0003);
    expect_reg(GPIO_IS, 32'h08, "W1C bits 1:0");
    apb_write(GPIO_IS, 32'hFFFF_FF00);
    expect_reg(GPIO_IS, 32'h08, "W1C reserved bits only");
    apb_write(GPIO_IS, 32'h0000_0008);
    expect_reg(GPIO_IS, 32'h00, "W1C bit 3");
    check(irq_gpio === 1'b0, "irq low with IS=0");
  endtask

  // Set and W1C clear of the same bit around the same clock edge.
  // d = (set edge) - (W1C access edge): -1 set first, 0 same edge, +1 set after.
  task automatic set_vs_clear(input int d, input logic exp);
    logic [31:0] r;
    int a, b;
    pins(8'h00);
    pins(8'h02);                      // IS[1] set by an earlier edge
    pins(8'h00);
    expect_reg(GPIO_IS, 32'h02, $sformatf("d=%0d: IS[1] set before", d));
    b = 2;                            // write called just after edge T+b -> access edge T+b+3
    a = b + 3 + d - edge_lat;         // pin change just after edge T+a -> set edge T+a+lat
    fork
      begin repeat (a) @(posedge clk); #1; gpio_i = 8'h02; end
      begin repeat (b) @(posedge clk); #1; apb_write(GPIO_IS, 32'h02); end
    join
    idle(4);
    apb_read(GPIO_IS, r);
    check(r === {30'd0, exp, 1'b0}, $sformatf("set vs W1C, d=%0d: IS=%h expected %h", d, r, {30'd0, exp, 1'b0}));
    apb_write(GPIO_IS, 32'hFF);
  endtask

  task automatic test_set_wins();
    $display("-- set and W1C in the same cycle (set wins)");
    item("GPIO-23");
    apb_write(GPIO_IE, 32'hFF);
    set_vs_clear(-1, 1'b0);
    set_vs_clear( 0, 1'b1);
    set_vs_clear( 1, 1'b1);
    pins(8'h00);
    apb_write(GPIO_IS, 32'hFF);
  endtask

  // GPIO-21: IE = 0 for all pins
  task automatic test_ie_zero();
    $display("-- IE = 0");
    item("GPIO-21");
    pins(8'h00);
    apb_write(GPIO_IS, 32'hFF);
    apb_write(GPIO_IE, 32'h00);
    pins(8'hFF);
    expect_reg(GPIO_IS, 32'h00, "IE = 0: no IS bit set by rising edges");
    check(irq_gpio === 1'b0, "IE = 0: irq low");
    pins(8'h00);
  endtask

  // GPIO-22: irq_gpio_o is the OR of IS AND IE, for each bit
  task automatic test_irq_or();
    $display("-- irq_gpio_o = OR(IS AND IE)");
    item("GPIO-22");
    apb_write(GPIO_IE, 32'hFF);
    for (int i = 0; i < 8; i++) begin
      pins(8'(1 << i));
      pins(8'h00);
      check(irq_gpio === 1'b1, $sformatf("irq high with only IS[%0d]", i));
      apb_write(GPIO_IE, 32'hFF ^ 32'(1 << i));
      check(irq_gpio === 1'b0, $sformatf("irq masked when IE[%0d] = 0", i));
      expect_reg(GPIO_IS, 32'(1 << i), $sformatf("IS[%0d] kept while masked", i));
      apb_write(GPIO_IE, 32'hFF);
      check(irq_gpio === 1'b1, $sformatf("irq back when IE[%0d] = 1", i));
      apb_write(GPIO_IS, 32'(1 << i));
      check(irq_gpio === 1'b0, $sformatf("irq low after clearing IS[%0d]", i));
    end
  endtask

  initial begin
    $display("tb_gpio_apb start");
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;
    idle(3);
    vp_regs();                                   // GPIO-01 .. GPIO-15
    item("GPIO-01"); test_reset_values();
    item("GPIO-02"); test_rw_regs();             // GPIO-16 / GPIO-10 inside
    test_input();                                // GPIO-17, 06, 18
    test_edges();                                // GPIO-18 .. 23
    test_ie_zero();
    test_irq_or();
    test_set_wins();
    $display("-- reset with pins High");
    item("GPIO-21");
    apb_write(GPIO_OUT, 32'hAA);
    apb_write(GPIO_OE,  32'h55);
    apb_write(GPIO_IE,  32'hFF);
    pins(8'h01);
    expect_reg(GPIO_IS, 32'h01, "IS set before reset");
    gpio_i = 8'hFF;
    #2 rst_n = 1'b0;
    #1 check(gpio_o === 8'h00 && gpio_oe === 8'h00 && irq_gpio === 1'b0, "outputs low in reset");
    idle(2);
    rst_n = 1'b1;
    idle(4);
    test_reset_values();
    apb_write(GPIO_IE, 32'hFF);
    idle(4);
    expect_reg(GPIO_IS, 32'h00, "no edge from pins already High when IE is set");
    check(irq_gpio === 1'b0, "irq low after reset with pins High");
    idle(2);
    vplan_pkg::report(VP_BLOCK, VP_N);
    $finish;
  end

endmodule
