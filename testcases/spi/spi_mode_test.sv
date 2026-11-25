// spi_mode_test: SPI-24..26, 32: SPI modes and clock divider
class spi_mode_test extends spi_base_test;
  function new();
    super.new();
    name = "spi_mode_test";
  endfunction

  virtual task run_scenario();
    test_modes(1'b0, "SPI-24");
    test_modes(1'b1, "SPI-25");
    test_div();
    test_cs();
  endtask

  task test_modes(input bit lsb, input string id);
    bit [7:0] dout[$], din[$];
    $display("%0t: [%s] modes 0..3, %s first", $time, name, lsb ? "LSB" : "MSB");
    item(id);
    for (int m = 0; m < 4; m++) begin
      // bytes whose bit order matters (not palindromes)
      dout = '{8'h01, 8'h80, 8'hC5};
      din  = '{8'h3A, 8'h02, 8'h7E};
      xfer(m[1], m[0], lsb, 2, dout, din, $sformatf("%s mode %0d", id, m));
      xfer_rand(m[1], m[0], lsb, 0, 3, $sformatf("%s mode %0d div 0", id, m));
      xfer_rand(m[1], m[0], lsb, 3, 2, $sformatf("%s mode %0d div 3", id, m));
    end
  endtask

  task test_div();
    $display("%0t: [%s] SCLK divider", $time, name);
    item("SPI-26");
    xfer_rand(0, 0, 0, 0,   4, "SPI-26 div 0");
    xfer_rand(1, 1, 0, 1,   3, "SPI-26 div 1");
    xfer_rand(0, 1, 1, 12,  2, "SPI-26 div 12");
    xfer_rand(1, 0, 0, 255, 1, "SPI-26 div 255");
    check(sb.n_err == 0, "SCLK half period = (clk_div + 1) clocks on every frame (scoreboard)");
  endtask

  task test_cs();
    bit [7:0] dout[$], din[$];
    $display("%0t: [%s] chip select", $time, name);
    item("SPI-32");
    // CS high: the frame still runs, the slave is not selected and leaves MISO at 1
    setup_mode(0, 0, 0, 1, 1'b0);
    write(TXDATA, 32'hA7);
    write(CTRL, C_EN);
    wait_frames(1);
    clks(2);
    check(spi_vif.cs_n === 1'b1, "CS = 1: spi_cs_no stays high during the frame");
    rd_check(RXDATA, 32'hFF, "CS = 1: no slave, MISO pulled up, RXDATA = FF");
    write(CTRL, 32'h0);
    // CS low: the slave answers
    dout = '{8'h5C};
    din  = '{8'h96};
    xfer(0, 0, 0, 1, dout, din, "SPI-32 CS low");
    check(spi_vif.cs_n === 1'b1, "CS = 1 after the transfer");
    // CS is software only: it does not change when a burst starts or ends
    slave(8'h33); slave(8'h44);
    write(CS, 32'h0);
    write(TXDATA, 32'h11);
    write(TXDATA, 32'h22);
    write(CTRL, C_EN);
    wait_frames(2);
    #1;
    check(spi_vif.cs_n === 1'b0, "spi_cs_no stays low after the burst until CS is written");
    rd_check(RXDATA, 32'h33, "CS held low: byte 0");
    rd_check(RXDATA, 32'h44, "CS held low: byte 1");
    write(CTRL, 32'h0);
    write(CS, 32'h1);
  endtask
endclass
