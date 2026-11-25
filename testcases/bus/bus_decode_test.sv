// bus_decode_test: BUS-01..05, 08: address decode and SRAM init file
class bus_decode_test extends bus_base_test;
  function new();
    super.new();
    name = "bus_decode_test";
  endfunction

  virtual task run_scenario();
    test_init_file();                  // first, before any write
    test_sram();
    test_unmapped();
    test_apb_slots();
    test_disabled_slots();
  endtask

  task test_init_file();
    $display("%0t: [%s] SRAM init file", $time, name);
    item("BUS-08");
    rd_exp(32'h0000_0000, 32'h4433_2211, 1'b0, "init file word 0");
    rd_exp(32'h0000_3FFC, 32'h8877_6655, 1'b0, "init file word 0xFFF");
  endtask

  task test_sram();
    int n_apb;
    $display("%0t: [%s] SRAM 0x0000_0000..0x0000_3FFF", $time, name);
    item("BUS-01");
    n_apb = sb.apb_log.size();
    wr(32'h0000_0000, 32'h0123_4567, 4'hF, 1'b0, "SRAM 0x0000");
    wr(32'h0000_2000, 32'h89AB_CDEF, 4'hF, 1'b0, "SRAM 0x2000");
    wr(32'h0000_3FFC, 32'hF0E1_D2C3, 4'hF, 1'b0, "SRAM 0x3FFC");
    check(sb.last_wr0.resp == OKAY, "SRAM write: BRESP OKAY");
    rd_exp(32'h0000_0000, 32'h0123_4567, 1'b0, "SRAM 0x0000");
    rd_exp(32'h0000_2000, 32'h89AB_CDEF, 1'b0, "SRAM 0x2000");
    rd_exp(32'h0000_3FFC, 32'hF0E1_D2C3, 1'b0, "SRAM 0x3FFC");
    check(sb.last_rd0.resp == OKAY, "SRAM read: RRESP OKAY");
    check(sb.apb_log.size() == n_apb, "an SRAM access started an APB transfer");
  endtask

  task unmapped(input string id, input bit [31:0] a);
    bit [31:0] r;
    bit        e;
    int        n_apb = sb.apb_log.size();
    int        n_sram = sb.n_sram;
    item(id);
    cpu(0, 1'b0, 1'b0, a, 32'h0, 4'h0, r, e);
    flush();
    check(e && sb.last_rd0.resp == DECERR && r == 32'h0,
          $sformatf("read %h: mem_err %b RRESP %b RDATA %h, expected DECERR and 0", a, e, sb.last_rd0.resp, r));
    cpu(0, 1'b1, 1'b0, a, 32'hDEAD_BEEF, 4'hF, r, e);
    flush();
    check(e && sb.last_wr0.resp == DECERR, $sformatf("write %h: mem_err %b BRESP %b, expected DECERR", a, e, sb.last_wr0.resp));
    check(sb.apb_log.size() == n_apb && sb.n_sram == n_sram, $sformatf("%h reached the SRAM or the APB bus", a));
  endtask

  task test_unmapped();
    $display("%0t: [%s] unmapped addresses", $time, name);
    unmapped("BUS-02", 32'h0000_4000);
    unmapped("BUS-02", 32'h0000_7FFC);
    unmapped("BUS-02", 32'h0001_0000);
    unmapped("BUS-02", 32'h0FFF_FFFC);
    unmapped("BUS-03", 32'h1001_0000);
    unmapped("BUS-03", 32'h2000_0000);
    unmapped("BUS-03", 32'hFFFF_FFFC);
    // the SRAM keeps its data (an alias of 0x4000 would overwrite word 0)
    item("BUS-02");
    rd_exp(32'h0000_0000, 32'h0123_4567, 1'b0, "SRAM word 0 after the unmapped writes");
  endtask

  task test_apb_slots();
    bit [31:0] a;
    $display("%0t: [%s] APB slots 0..5", $time, name);
    item("BUS-04");
    for (int s = 0; s < 6; s++) begin
      a = 32'h1000_0000 | (s << 12);
      wr(a, 32'hA500_0000 | s, 4'hF, 1'b0, $sformatf("slot %0d", s));
      flush();
      check(sb.apb_log.size() > 0 && sb.apb_log[$].slot == s && sb.apb_log[$].addr[11:0] == 12'h000 && sb.apb_log[$].we,
            $sformatf("write to slot %0d: APB went to slot %0d", s, sb.apb_log[$].slot));
      check(sb.last_wr0.resp == OKAY, $sformatf("slot %0d write: BRESP %b", s, sb.last_wr0.resp));
      rd_exp(a, 32'hA500_0000 | s, 1'b0, $sformatf("slot %0d", s));
      flush();
      check(sb.apb_log[$].slot == s && !sb.apb_log[$].we, $sformatf("read of slot %0d: APB slot %0d", s, sb.apb_log[$].slot));
      check(sb.last_rd0.resp == OKAY, $sformatf("slot %0d read: RRESP %b", s, sb.last_rd0.resp));
    end
    // PADDR = ADDR[11:0]
    wr(32'h1000_2ABC, 32'h0000_0ABC, 4'hF, 1'b0, "slot 2 offset 0xABC");
    flush();
    check(sb.apb_log[$].slot == 2 && sb.apb_log[$].addr[11:0] == 12'hABC,
          $sformatf("PADDR %h, expected ABC", sb.apb_log[$].addr[11:0]));
    rd_exp(32'h1000_2ABC, 32'h0000_0ABC, 1'b0, "slot 2 offset 0xABC");
    check(pslv.mem[2][12'hABC >> 2] == 32'h0000_0ABC, "APB slave memory of slot 2");
  endtask

  task test_disabled_slots();
    bit [31:0] a, r;
    bit        e;
    int        n_apb;
    $display("%0t: [%s] APB slots 6..15 (disabled)", $time, name);
    item("BUS-05");
    for (int s = 6; s < 16; s++) begin
      a = 32'h1000_0000 | (s << 12) | ((s == 15) ? 32'hFFC : 32'h0);
      n_apb = sb.apb_log.size();
      cpu(0, 1'b0, 1'b0, a, 32'h0, 4'h0, r, e);
      flush();
      check(e && sb.last_rd0.resp == SLVERR && r == 32'h0,
            $sformatf("read %h: mem_err %b RRESP %b RDATA %h, expected SLVERR and 0", a, e, sb.last_rd0.resp, r));
      cpu(0, 1'b1, 1'b0, a, 32'h1234_5678, 4'hF, r, e);
      flush();
      check(e && sb.last_wr0.resp == SLVERR, $sformatf("write %h: BRESP %b, expected SLVERR", a, sb.last_wr0.resp));
      check(sb.apb_log.size() == n_apb, $sformatf("%h started an APB transfer", a));
    end
  endtask
endclass
