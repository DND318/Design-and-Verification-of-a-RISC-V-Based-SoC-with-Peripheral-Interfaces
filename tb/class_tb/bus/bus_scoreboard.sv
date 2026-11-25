// Bus scoreboard (reference model)
class bus_scoreboard;
  mailbox #(bus_packet) m2s_mb;

  // SRAM model: 4096 words, a byte is compared only when it is known
  bit [31:0]   sram_d[int];
  bit [3:0]    sram_k[int];

  // packets waiting to be matched
  bus_packet   q0[$];           // xbar input, from the master adapter, waiting for the CPU packet
  bus_packet   q1[$];           // SRAM port
  bus_packet   qa[$];           // APB transfers
  bus_packet   q2[$];           // second master
  // for the tests
  bus_packet   apb_log[$];      // every APB transfer
  bus_packet   last_wr0, last_rd0;   // last write / read on the xbar input

  int unsigned n_cpu, n_axi0, n_sram, n_apb, n_axi2, n_err;
  bit          verbose;
  bit          en_fc = 1'b1;
  `include "coverage.sv"

  typedef enum int {T_SRAM, T_APB, T_APB_OFF, T_ERR} target_e;

  function new(mailbox #(bus_packet) m2s_mb);
    this.m2s_mb = m2s_mb;
    verbose = $test$plusargs("VERBOSE");
    last_wr0 = new();
    last_rd0 = new();
    // init file (tb/test_vectors/bus_init_b*.hex): word 0 and word 0xFFF
    sram_d[0]     = 32'h4433_2211; sram_k[0]     = 4'hF;
    sram_d[12'hFFF] = 32'h8877_6655; sram_k[12'hFFF] = 4'hF;
`ifndef VERILATOR
    AXI_GROUP = new();
    APB_GROUP = new();
    M2_GROUP  = new();
`endif
  endfunction

  function void check(bit ok, string what);
    if (!ok) n_err++;
    vplan_pkg::chk(ok, what);
  endfunction

  static function target_e target(bit [31:0] a);
    if (a[31:14] == 18'd0)       return T_SRAM;
    if (a[31:16] == 16'h1000)    return (a[15:12] < 4'd6) ? T_APB : T_APB_OFF;
    return T_ERR;
  endfunction

  static function string tname(target_e t);
    case (t)
      T_SRAM:    return "SRAM";
      T_APB:     return "APB";
      T_APB_OFF: return "disabled APB slot";
      default:   return "unmapped";
    endcase
  endfunction

  // First packet of q with the same direction (removed from q)
  function bus_packet take(ref bus_packet q[$], input bit we);
    bus_packet p;
    foreach (q[i]) if (q[i].we == we) begin
      p = q[i];
      q.delete(i);
      return p;
    end
    return null;
  endfunction

  function bit has(ref bus_packet q[$], input bit we);
    foreach (q[i]) if (q[i].we == we) return 1;
    return 0;
  endfunction

  task run();
    bus_packet p;
    while (1) begin
      m2s_mb.get(p);
      case (p.kind)
        BUS_APB: begin
          n_apb++;
          qa.push_back(p);
          apb_log.push_back(p);
          if (en_fc) sample_apb_fc(p);
        end
        BUS_AXI_WR, BUS_AXI_RD: begin
          if (p.port == 0)      axi0(p);
          else if (p.port == 1) begin n_sram++; q1.push_back(p); end
          else                  begin n_axi2++; q2.push_back(p); if (en_fc) sample_m2_fc(p); end
        end
        BUS_CPU: cpu(p);
        default: ;
      endcase
    end
  endtask

  // One transaction on the xbar input
  function void axi0(bus_packet t);
    target_e   tg = target(t.addr);
    bus_packet d;
    string     dir = t.we ? "write" : "read";
    bit [31:0] exp;
    bit [31:0] m;
    int        w;
    n_axi0++;
    if (t.we) last_wr0 = t; else last_rd0 = t;
    if (en_fc) sample_axi_fc(t, int'(tg));
    if (verbose) $display("%0t: [scoreboard] %s %h -> %s", $time, dir, t.addr, tname(tg));
    case (tg)
      T_SRAM: begin
        d = take(q1, t.we);
        check(d != null, $sformatf("[scoreboard] %s %h: no transaction on the SRAM port", dir, t.addr));
        check(!has(qa, t.we), $sformatf("[scoreboard] %s %h (SRAM): an APB transfer was made", dir, t.addr));
        check(t.resp == 2'b00, $sformatf("[scoreboard] %s %h (SRAM): RESP %b, expected OKAY", dir, t.addr, t.resp));
        if (d != null) begin
          check(d.addr == t.addr && d.prot == t.prot && (!t.we || (d.wdata == t.wdata && d.wstrb == t.wstrb)),
                $sformatf("[scoreboard] %s %h: SRAM port saw %h prot %b data %h strb %b", dir, t.addr,
                          d.addr, d.prot, d.wdata, d.wstrb));
          check(d.resp == t.resp && (t.we || d.rdata == t.rdata),
                $sformatf("[scoreboard] %s %h: response changed in the xbar", dir, t.addr));
        end
        w = int'(t.addr[13:2]);
        if (t.we) begin
          if (!sram_d.exists(w)) begin sram_d[w] = 0; sram_k[w] = 0; end
          for (int b = 0; b < 4; b++)
            if (t.wstrb[b]) begin
              sram_d[w][8*b +: 8] = t.wdata[8*b +: 8];
              sram_k[w][b] = 1'b1;
            end
        end else if (sram_d.exists(w)) begin
          m = {{8{sram_k[w][3]}}, {8{sram_k[w][2]}}, {8{sram_k[w][1]}}, {8{sram_k[w][0]}}};
          check((t.rdata & m) == (sram_d[w] & m),
                $sformatf("[scoreboard] SRAM read %h = %h, expected %h (mask %h)", t.addr, t.rdata, sram_d[w], m));
        end
      end
      T_APB: begin
        d = take(qa, t.we);
        check(d != null, $sformatf("[scoreboard] %s %h: no APB transfer", dir, t.addr));
        check(!has(q1, t.we), $sformatf("[scoreboard] %s %h (APB): the SRAM port was used", dir, t.addr));
        if (d != null) begin
          check(d.slot == int'(t.addr[15:12]) && d.addr[11:0] == t.addr[11:0],
                $sformatf("[scoreboard] %s %h: APB slot %0d PADDR %h, expected slot %0d PADDR %h", dir, t.addr,
                          d.slot, d.addr[11:0], t.addr[15:12], t.addr[11:0]));
          check(d.prot == t.prot, $sformatf("[scoreboard] %s %h: PPROT %b, AxPROT %b", dir, t.addr, d.prot, t.prot));
          if (t.we)
            check(d.wdata == t.wdata && d.wstrb == t.wstrb,
                  $sformatf("[scoreboard] write %h: PWDATA %h PSTRB %b, expected %h / %b", t.addr, d.wdata, d.wstrb,
                            t.wdata, t.wstrb));
          else
            check(d.wstrb == 4'h0, $sformatf("[scoreboard] read %h: PSTRB %b, expected 0000", t.addr, d.wstrb));
          exp = d.pslverr ? 2'b10 : 2'b00;
          check(t.resp == exp[1:0], $sformatf("[scoreboard] %s %h: RESP %b, PSLVERR %b", dir, t.addr, t.resp, d.pslverr));
          if (!t.we)
            check(t.rdata == d.rdata, $sformatf("[scoreboard] read %h: RDATA %h, PRDATA %h", t.addr, t.rdata, d.rdata));
        end
      end
      T_APB_OFF: begin
        check(!has(qa, t.we), $sformatf("[scoreboard] %s %h (slot %0d is disabled): an APB transfer was made",
                                        dir, t.addr, t.addr[15:12]));
        check(t.resp == 2'b10, $sformatf("[scoreboard] %s %h (disabled slot): RESP %b, expected SLVERR", dir, t.addr, t.resp));
        if (!t.we) check(t.rdata == 32'h0, $sformatf("[scoreboard] read %h (disabled slot): RDATA %h, expected 0", t.addr, t.rdata));
      end
      default: begin
        check(!has(q1, t.we) && !has(qa, t.we),
              $sformatf("[scoreboard] %s %h (unmapped): reached the %s", dir, t.addr, has(q1, t.we) ? "SRAM" : "APB bus"));
        void'(take(q1, t.we));
        void'(take(qa, t.we));
        check(t.resp == 2'b11, $sformatf("[scoreboard] %s %h (unmapped): RESP %b, expected DECERR", dir, t.addr, t.resp));
        if (!t.we) check(t.rdata == 32'h0, $sformatf("[scoreboard] read %h (unmapped): RDATA %h, expected 0", t.addr, t.rdata));
      end
    endcase
    if (!t.direct) q0.push_back(t);
  endfunction

  // One CPU request against the AXI transaction made from it
  function void cpu(bus_packet c);
    bus_packet t;
    string     dir = c.we ? "write" : "read";
    n_cpu++;
    if (c.port == 0) begin
      if (q0.size() != 0) t = q0.pop_front(); else t = null;
    end else begin
      if (q2.size() != 0) t = q2.pop_front(); else t = null;
    end
    check(t != null, $sformatf("[scoreboard] CPU port %0d %s %h: mem_ready without an AXI transaction", c.port, dir, c.addr));
    if (t == null) return;
    check(t.we == c.we && t.addr == c.addr,
          $sformatf("[scoreboard] CPU port %0d %s %h: AXI %s %h", c.port, dir, c.addr, t.we ? "write" : "read", t.addr));
    check(t.prot == {c.instr, 2'b01},
          $sformatf("[scoreboard] CPU port %0d %s %h instr=%b: AxPROT %b, expected %b", c.port, dir, c.addr, c.instr,
                    t.prot, {c.instr, 2'b01}));
    if (c.we)
      check(t.wdata == c.wdata && t.wstrb == c.wstrb,
            $sformatf("[scoreboard] CPU port %0d write %h: WDATA %h WSTRB %b, expected %h / %b", c.port, c.addr,
                      t.wdata, t.wstrb, c.wdata, c.wstrb));
    check(c.err == t.resp[1], $sformatf("[scoreboard] CPU port %0d %s %h: mem_err %b, RESP %b", c.port, dir, c.addr, c.err, t.resp));
    if (!c.we)
      check(c.rdata == t.rdata, $sformatf("[scoreboard] CPU port %0d read %h: mem_rdata %h, RDATA %h", c.port, c.addr,
                                          c.rdata, t.rdata));
  endfunction

  // Everything matched at the end of the test
  function void final_check();
    int n0 = 0;
    foreach (q0[i]) n0++;
    check(n0 == 0 && q1.size() == 0 && qa.size() == 0 && q2.size() == 0,
          $sformatf("[scoreboard] unmatched at the end: %0d xbar, %0d SRAM, %0d APB, %0d master 2", n0, q1.size(),
                    qa.size(), q2.size()));
  endfunction

  function void report();
    $display("%0t: [scoreboard] %0d CPU requests, %0d xbar transactions, %0d SRAM, %0d APB, %0d master 2, %0d mismatches",
             $time, n_cpu, n_axi0, n_sram, n_apb, n_axi2, n_err);
    report_fc();
  endfunction
endclass
