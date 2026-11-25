// bus_sram_test: BUS-06, 07: SRAM byte enables, back-to-back access
class bus_sram_test extends bus_base_test;
  function new();
    super.new();
    name = "bus_sram_test";
  endfunction

  virtual task run_scenario();
    test_strobes();
    test_b2b();
  endtask

  task test_strobes();
    bit [31:0] exp;
    bit [3:0]  sv[$];
    $display("%0t: [%s] SRAM byte enables", $time, name);
    item("BUS-06");
    for (int k = 1; k < 16; k++) sv.push_back(4'(k));          // every WSTRB value
    foreach (sv[k]) begin
      wr(32'h0000_0100, 32'hFFFF_FFFF, 4'hF, 1'b0, "SRAM all ones");
      wr(32'h0000_0100, 32'h0000_0000, sv[k], 1'b0, $sformatf("SRAM WSTRB %b", sv[k]));
      exp = 32'hFFFF_FFFF;
      for (int b = 0; b < 4; b++) if (sv[k][b]) exp[8*b +: 8] = 8'h00;
      rd_exp(32'h0000_0100, exp, 1'b0, $sformatf("SRAM after WSTRB %b", sv[k]));
    end
    // byte writes to the four lanes of one word, then one word read
    wr(32'h0000_0104, 32'h0000_00A1, 4'b0001, 1'b0, "lane 0");
    wr(32'h0000_0104, 32'h0000_B200, 4'b0010, 1'b0, "lane 1");
    wr(32'h0000_0104, 32'h00C3_0000, 4'b0100, 1'b0, "lane 2");
    wr(32'h0000_0104, 32'hD400_0000, 4'b1000, 1'b0, "lane 3");
    rd_exp(32'h0000_0104, 32'hD4C3_B2A1, 1'b0, "four byte writes");
  endtask

  task test_b2b();
    bit [31:0] r, a;
    bit        e;
    $display("%0t: [%s] back-to-back SRAM reads and writes", $time, name);
    item("BUS-07");
    for (int i = 0; i < 8; i++) wr(32'h0000_0200 + 4 * i, 32'h5000_0000 + i * 32'h0101_0101, 4'hF, 1'b0, "fill");
    for (int i = 0; i < 8; i++) begin
      a = 32'h0000_0200 + 4 * ((i * 3) % 8);
      cpu(0, 1'b0, 1'b0, a, 32'h0, 4'h0, r, e, i != 7);     // mem_req stays high
      check(r == 32'h5000_0000 + ((i * 3) % 8) * 32'h0101_0101 && !e,
            $sformatf("back-to-back read %0d: %h = %h", i, a, r));
    end
    // writes and reads mixed, back to back
    for (int i = 0; i < 8; i++) begin
      a = 32'h0000_0300 + 4 * i;
      cpu(0, 1'b1, 1'b0, a, ~a, 4'hF, r, e, 1'b1);
      cpu(0, 1'b0, 1'b0, a, 32'h0, 4'h0, r, e, i != 7);
      check(r == ~a && !e, $sformatf("write then read back to back %h = %h", a, r));
    end
    flush();
    check(sb.last_rd0.cyc >= 1, $sformatf("SRAM read latency %0d cycles", sb.last_rd0.cyc));
  endtask
endclass
