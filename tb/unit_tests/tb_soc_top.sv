// System-level testbench for soc_top: runs a firmware image from sw/build.
// Plusargs:
//   +PROG=<prefix>     program files <prefix>.b0.hex .. .b3.hex (scripts/elf2hex.py)
//   +BAUD_DIV=<n>      UART bit period - 1 used by the firmware (default 433)
//   +MAXCYC=<n>        timeout in clock cycles (default 3000000)
// Board-level models: UART line decoder on uart_tx_o (prints every line),
// SPI MOSI->MISO loopback, I2C bus with pull-ups and a 24LC32A EEPROM model
// at address 0x50, GPIO outputs looped back to the inputs.
// The firmware ends the test by printing a line "@@PASS" or "@@FAIL ...".
// Ends with "TEST PASSED" or "TEST FAILED" for scripts/check_log.sh.
`timescale 1ns/1ps
module tb_soc_top;

  logic       clk = 1'b0;
  logic       rst_n = 1'b0;

  wire        uart_tx;
  logic       uart_rx = 1'b1;
  wire        spi_sclk, spi_mosi, spi_cs_n;
  wire        i2c_scl_o, i2c_scl_oe, i2c_sda_o, i2c_sda_oe;
  wire [7:0]  gpio_o, gpio_oe;

  string       prog;
  int unsigned baud_div, max_cyc;
  int unsigned cycle = 0;
  int unsigned errors = 0;

  always #10 clk = ~clk;   // 50 MHz

  // ---------------- I2C bus: wired-AND with pull-ups ----------------
  wire eeprom_sda_drive_low;
  wire scl_line = !i2c_scl_oe;
  wire sda_line = !(i2c_sda_oe || eeprom_sda_drive_low);

  i2c_eeprom_24lc32a #(.DEV_ADDR(7'h50)) u_eeprom (
    .scl_i           (scl_line),
    .sda_i           (sda_line),
    .sda_drive_low_o (eeprom_sda_drive_low)
  );

  soc_top dut (
    .clk_i        (clk),
    .rst_ni       (rst_n),
    .uart_tx_o    (uart_tx),
    .uart_rx_i    (uart_rx),
    .spi_sclk_o   (spi_sclk),
    .spi_mosi_o   (spi_mosi),
    .spi_miso_i   (spi_mosi),       // loopback
    .spi_cs_no    (spi_cs_n),
    .i2c_scl_o    (i2c_scl_o),
    .i2c_scl_oe_o (i2c_scl_oe),
    .i2c_scl_i    (scl_line),
    .i2c_sda_o    (i2c_sda_o),
    .i2c_sda_oe_o (i2c_sda_oe),
    .i2c_sda_i    (sda_line),
    .gpio_o       (gpio_o),
    .gpio_oe_o    (gpio_oe),
    .gpio_i       (gpio_o)          // loopback
  );

  // ---------------- control ----------------
  task automatic finish_test();
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED");
    $finish;
  endtask

  always @(posedge clk) begin
    cycle <= cycle + 1;
    if (cycle >= max_cyc) begin
      $display("[%0t] ERROR: timeout after %0d cycles", $time, cycle);
      errors++;
      finish_test();
    end
  end

  // ---------------- UART line decoder ----------------
  string line = "";

  task automatic end_of_line();
    $display("[%0t] UART: %s", $time, line);
    if (line.len() >= 6 && line.substr(0, 5) == "@@PASS") begin
      finish_test();
    end else if (line.len() >= 6 && line.substr(0, 5) == "@@FAIL") begin
      $display("ERROR: firmware reported failure");
      errors++;
      finish_test();
    end
    line = "";
  endtask

  initial begin : uart_decoder
    logic [7:0] ch;
    @(posedge rst_n);
    forever begin
      @(negedge uart_tx);
      repeat ((baud_div + 1) / 2) @(posedge clk);
      if (uart_tx != 1'b0) continue;          // glitch, not a start bit
      for (int b = 0; b < 8; b++) begin
        repeat (baud_div + 1) @(posedge clk);
        ch[b] = uart_tx;
      end
      repeat (baud_div + 1) @(posedge clk);
      if (uart_tx != 1'b1) begin
        $display("[%0t] ERROR: UART framing error on tx", $time);
        errors++;
      end
      if (ch == 8'h0A)       end_of_line();
      else if (ch != 8'h0D)  line = {line, string'(ch)};
    end
  end

  // ---------------- start ----------------
  initial begin
    if (!$value$plusargs("PROG=%s", prog)) begin
      $display("ERROR: +PROG=<prefix> missing");
      $display("TEST FAILED");
      $finish;
    end
    if (!$value$plusargs("BAUD_DIV=%d", baud_div)) baud_div = 433;
    if (!$value$plusargs("MAXCYC=%d", max_cyc)) max_cyc = 3000000;
    $readmemh({prog, ".b0.hex"}, dut.u_sram.u_ram.lane0);
    $readmemh({prog, ".b1.hex"}, dut.u_sram.u_ram.lane1);
    $readmemh({prog, ".b2.hex"}, dut.u_sram.u_ram.lane2);
    $readmemh({prog, ".b3.hex"}, dut.u_sram.u_ram.lane3);
    $display("program %s, UART baud_div %0d", prog, baud_div);
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // Pins the board models do not look at (SPI loopback only uses MOSI,
  // the I2C bus uses only the output enables)
  wire unused_pins = &{1'b0, spi_sclk, spi_cs_n, i2c_scl_o, i2c_sda_o, gpio_oe};

endmodule
