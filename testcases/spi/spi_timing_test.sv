// spi_timing_test: SPI-27..29: data timing
class spi_timing_test extends spi_base_test;
  function new();
    super.new();
    name = "spi_timing_test";
  endfunction

  virtual task run_scenario();
    test_setup_hold();
    test_miso_sampling();
    test_back_to_back();
  endtask

  task test_setup_hold();
    bit [7:0] dout[$], din[$];
    int unsigned divs[3] = '{0, 2, 7};
    $display("%0t: [%s] MOSI setup / hold", $time, name);
    item("SPI-27");
    for (int m = 0; m < 4; m++)
      foreach (divs[k]) begin
        dout = '{8'h55, 8'hAA, 8'h0F};
        din  = '{8'hAA, 8'h55, 8'hF0};
        xfer(m[1], m[0], m[0] ^ m[1], divs[k], dout, din,
             $sformatf("SPI-27 mode %0d div %0d", m, divs[k]));
      end
    check(sb.n_err == 0, "MOSI setup / hold >= half a SCLK period (scoreboard)");
  endtask

  task test_miso_sampling();
    bit [7:0] dout[$], din[$];
    int unsigned dly[5] = '{1, 5, 10, 15, 19};
    $display("%0t: [%s] MISO sampling at clk_div = 0", $time, name);
    item("SPI-28");
    foreach (dly[k]) begin
      cfg.miso_dly = dly[k];
      for (int m = 0; m < 4; m++) begin
        din  = '{8'hA5, 8'h5A, 8'hFF, 8'h00, 8'h81};
        dout = '{8'h3C, 8'h00, 8'hFF, 8'h96, 8'h18};
        xfer(m[1], m[0], m[0], 0, dout, din, $sformatf("SPI-28 MISO %0d ns after the shift edge, mode %0d", dly[k], m));
      end
    end
    cfg.miso_dly = 3;
  endtask

  task test_back_to_back();
    $display("%0t: [%s] back-to-back frames", $time, name);
    item("SPI-29");
    xfer_rand(0, 0, 0, 0, 16, "SPI-29 div 0 mode 0");
    xfer_rand(1, 1, 0, 0, 16, "SPI-29 div 0 mode 3");
    xfer_rand(0, 1, 1, 3, 16, "SPI-29 div 3 mode 1");
    xfer_rand(1, 0, 1, 1, 8,  "SPI-29 div 1 mode 2");
    check(sb.n_err == 0, "back-to-back gap <= half period + 3 clocks (scoreboard)");
  endtask
endclass
