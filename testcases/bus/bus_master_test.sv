// bus_master_test: BUS-14..16: AXI master handshake, response, AxPROT
class bus_master_test extends bus_base_test;
  function new();
    super.new();
    name = "bus_master_test";
  endfunction

  virtual task run_scenario();
    test_handshake();
    test_resp();
    test_prot();
  endtask

  task test_handshake();
    bit [31:0] a, r;
    bit        e;
    $display("%0t: [%s] VALID / READY with random slave delays", $time, name);
    item("BUS-14");
    aslv.resp = OKAY;
    for (int i = 0; i < 40; i++) begin
      a = 32'h2000_0000 + 4 * i;
      cpu(1, 1'b1, 1'b0, a, ~a, 4'(i % 15 + 1), r, e);
      check(aslv.last_awaddr == a && aslv.last_wdata == ~a && aslv.last_wstrb == 4'(i % 15 + 1),
            $sformatf("write %0d: slave saw %h / %h / %b", i, aslv.last_awaddr, aslv.last_wdata, aslv.last_wstrb));
      cpu(1, 1'b0, 1'b0, a, 32'h0, 4'h0, r, e);
      check(aslv.last_araddr == a && r == ~a, $sformatf("read %0d: slave saw %h, data %h", i, aslv.last_araddr, r));
    end
    // back to back on the second master
    for (int i = 0; i < 10; i++) begin
      a = 32'h2000_1000 + 4 * i;
      cpu(1, i[0], 1'b0, a, a, 4'hF, r, e, i != 9);
      if (!i[0]) check(r == ~a, $sformatf("back-to-back read %h = %h", a, r));
    end
  endtask

  task test_resp();
    bit [1:0]  rs[4] = '{OKAY, EXOKAY, SLVERR, DECERR};
    bit [31:0] r;
    bit        e;
    $display("%0t: [%s] response codes and mem_err", $time, name);
    item("BUS-15");
    foreach (rs[k]) begin
      aslv.resp = rs[k];
      cpu(1, 1'b0, 1'b0, 32'h3000_0000, 32'h0, 4'h0, r, e);
      check(e == rs[k][1], $sformatf("read RRESP %b: mem_err %b", rs[k], e));
      cpu(1, 1'b1, 1'b0, 32'h3000_0000, 32'h0, 4'hF, r, e);
      check(e == rs[k][1], $sformatf("write BRESP %b: mem_err %b", rs[k], e));
    end
    aslv.resp = OKAY;
    // main path: OKAY (SRAM, APB), SLVERR (disabled slot), DECERR (unmapped)
    wr(32'h0000_0010, 32'h1111_2222, 4'hF, 1'b0, "OKAY from the SRAM");
    rd_exp(32'h0000_0010, 32'h1111_2222, 1'b0, "OKAY from the SRAM");
    rd_exp(32'h1000_5000, 32'h0, 1'b0, "OKAY from APB slot 5");
    rd_exp(32'h1000_7000, 32'h0, 1'b1, "SLVERR on the main path");
    wr(32'h1000_7000, 32'h0, 4'hF, 1'b1, "SLVERR on the main path");
    rd_exp(32'h0000_4000, 32'h0, 1'b1, "DECERR on the main path");
    wr(32'h0000_4000, 32'h0, 4'hF, 1'b1, "DECERR on the main path");
    rd_exp(32'h0000_0010, 32'h1111_2222, 1'b0, "SRAM unchanged after the DECERR write");
  endtask

  task test_prot();
    bit [31:0] r;
    bit        e;
    $display("%0t: [%s] AxPROT from mem_instr", $time, name);
    item("BUS-16");
    cpu(1, 1'b0, 1'b1, 32'h0000_0100, 32'h0, 4'h0, r, e);
    check(aslv.last_arprot == 3'b101, $sformatf("fetch: ARPROT %b, expected 101", aslv.last_arprot));
    cpu(1, 1'b0, 1'b0, 32'h0000_0104, 32'h0, 4'h0, r, e);
    check(aslv.last_arprot == 3'b001, $sformatf("data load: ARPROT %b, expected 001", aslv.last_arprot));
    cpu(1, 1'b1, 1'b0, 32'h0000_0108, 32'h0, 4'hF, r, e);
    check(aslv.last_awprot == 3'b001, $sformatf("data store: AWPROT %b, expected 001", aslv.last_awprot));
    cpu(0, 1'b0, 1'b1, 32'h0000_0000, 32'h0, 4'h0, r, e);
    flush();
    check(sb.last_rd0.prot == 3'b101, $sformatf("main path fetch: ARPROT %b, expected 101", sb.last_rd0.prot));
  endtask
endclass
