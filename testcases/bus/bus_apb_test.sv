// bus_apb_test: BUS-09..13, 16: APB protocol, wait states, PSLVERR, write/read order
class bus_apb_test extends bus_base_test;
  function new();
    super.new();
    name = "bus_apb_test";
  endfunction

  virtual task run_scenario();
    test_protocol();
    test_wait_states();
    test_pslverr();
    test_order();
  endtask

  function bus_packet last_apb();
    return sb.apb_log[sb.apb_log.size() - 1];
  endfunction

  task test_protocol();
    int        n_apb;
    bit [31:0] r;
    bit        e;
    $display("%0t: [%s] APB SETUP / ACCESS, PSTRB / PPROT", $time, name);
    item("BUS-09");
    n_apb = sb.apb_log.size();
    wr(32'h1000_0040, 32'h1357_9BDF, 4'hF, 1'b0, "slot 0 write");
    rd_exp(32'h1000_0040, 32'h1357_9BDF, 1'b0, "slot 0 read");
    flush();
    check(sb.apb_log.size() == n_apb + 2, "one APB transfer per AXI transaction");
    item("BUS-10");
    wr(32'h1000_0044, 32'hFFFF_FFFF, 4'hF, 1'b0, "PSTRB 1111");
    flush();
    check(last_apb().wstrb == 4'hF && last_apb().prot == 3'b001,
          $sformatf("write WSTRB 1111: PSTRB %b PPROT %b", last_apb().wstrb, last_apb().prot));
    for (int k = 1; k < 15; k++) begin
      wr(32'h1000_1048, 32'($urandom), 4'(k), 1'b0, $sformatf("PSTRB %b", 4'(k)));
      flush();
      check(last_apb().wstrb == 4'(k), $sformatf("write WSTRB %b: PSTRB %b", 4'(k), last_apb().wstrb));
    end
    wr(32'h1000_0044, 32'h0000_0000, 4'b0001, 1'b0, "PSTRB 0001");
    rd_exp(32'h1000_0044, 32'hFFFF_FF00, 1'b0, "after PSTRB 0001");
    flush();
    check(last_apb().wstrb == 4'b0000 && !last_apb().we && last_apb().prot == 3'b001,
          $sformatf("read: PSTRB %b PPROT %b, expected 0000 / 001", last_apb().wstrb, last_apb().prot));
    item("BUS-16");
    cpu(0, 1'b0, 1'b1, 32'h1000_0044, 32'h0, 4'h0, r, e);
    flush();
    check(last_apb().prot == 3'b101, $sformatf("instruction fetch: PPROT %b, expected 101", last_apb().prot));
    cpu(0, 1'b0, 1'b1, 32'h0000_0000, 32'h0, 4'h0, r, e);
    flush();
    check(sb.last_rd0.prot == 3'b101, $sformatf("fetch from the SRAM: ARPROT %b, expected 101", sb.last_rd0.prot));
  endtask

  task test_wait_states();
    int ws[5] = '{0, 1, 2, 5, 9};
    $display("%0t: [%s] APB wait states", $time, name);
    item("BUS-11");
    foreach (ws[k]) begin
      pslv.wait_n[k % 6] = ws[k];
      wr(32'h1000_0080 | ((k % 6) << 12), 32'hC0DE_0000 + ws[k], 4'hF, 1'b0, $sformatf("%0d wait states", ws[k]));
      flush();
      check(last_apb().waits == ws[k], $sformatf("write: %0d wait cycles seen, expected %0d", last_apb().waits, ws[k]));
      rd_exp(32'h1000_0080 | ((k % 6) << 12), 32'hC0DE_0000 + ws[k], 1'b0, $sformatf("%0d wait states", ws[k]));
      flush();
      check(last_apb().waits == ws[k], $sformatf("read: %0d wait cycles seen, expected %0d", last_apb().waits, ws[k]));
      pslv.wait_n[k % 6] = 0;
    end
  endtask

  task test_pslverr();
    bit [31:0] r;
    bit        e;
    $display("%0t: [%s] PSLVERR", $time, name);
    item("BUS-12");
    pslv.err_rd[3] = 1'b1;
    pslv.err_wr[3] = 1'b1;
    pslv.wait_n[3] = 2;
    cpu(0, 1'b0, 1'b0, 32'h1000_3010, 32'h0, 4'h0, r, e);
    flush();
    check(e && sb.last_rd0.resp == SLVERR, $sformatf("PSLVERR on a read: mem_err %b RRESP %b", e, sb.last_rd0.resp));
    cpu(0, 1'b1, 1'b0, 32'h1000_3010, 32'h1, 4'hF, r, e);
    flush();
    check(e && sb.last_wr0.resp == SLVERR, $sformatf("PSLVERR on a write: mem_err %b BRESP %b", e, sb.last_wr0.resp));
    pslv.err_rd[3] = 1'b0;
    pslv.err_wr[3] = 1'b0;
    pslv.wait_n[3] = 0;
    wr(32'h1000_3010, 32'h0000_0077, 4'hF, 1'b0, "slot 3 after PSLVERR");
    flush();
    check(sb.last_wr0.resp == OKAY, "OKAY again after PSLVERR");
    rd_exp(32'h1000_3010, 32'h0000_0077, 1'b0, "slot 3 after PSLVERR");
  endtask

  task order_case(input bit [31:0] wa, input bit [31:0] ra, input bit [31:0] rexp);
    bit [1:0]  br, rr;
    bit [31:0] rdat;
    int        n_apb = sb.apb_log.size();
    direct(wa, 32'h600D_CAFE ^ wa, ra, br, rr, rdat);
    flush();
    check(sb.apb_log.size() == n_apb + 2, $sformatf("%0d APB transfers, expected 2", sb.apb_log.size() - n_apb));
    if (sb.apb_log.size() == n_apb + 2) begin
      check(sb.apb_log[n_apb].we && sb.apb_log[n_apb].addr[11:0] == wa[11:0],
            $sformatf("write %h and read %h in the same cycle: the first APB transfer is not the write", wa, ra));
      check(!sb.apb_log[n_apb + 1].we && sb.apb_log[n_apb + 1].addr[11:0] == ra[11:0],
            "the second APB transfer is not the read");
    end
    check(br == OKAY && rr == OKAY && rdat == rexp,
          $sformatf("BRESP %b RRESP %b read data %h, expected OKAY / %h", br, rr, rdat, rexp));
  endtask

  task test_order();
    $display("%0t: [%s] write and read valid in the same cycle", $time, name);
    item("BUS-13");
    pslv.mem[0][8] = 32'h0BAD_F00D;                // slot 0 offset 0x020
    order_case(32'h1000_0010, 32'h1000_0020, 32'h0BAD_F00D);
    rd_exp(32'h1000_0010, 32'h600D_CAFE ^ 32'h1000_0010, 1'b0, "write data after the same-cycle case");
    // read of the address being written: the write goes first
    order_case(32'h1000_1030, 32'h1000_1030, 32'h600D_CAFE ^ 32'h1000_1030);
    pslv.wait_n[4] = 3;
    order_case(32'h1000_4000, 32'h1000_4000, 32'h600D_CAFE ^ 32'h1000_4000);
    pslv.wait_n[4] = 0;
  endtask
endclass
