// bus_rand_test: random traffic on all ports (BUS-RND)
class bus_rand_test extends bus_base_test;
  function new();
    super.new();
    name = "bus_rand_test";
  endfunction

  virtual task run_scenario();
    int n = 20;
    void'($value$plusargs("N=%d", n));
    $display("%0t: [%s] %0d random rounds", $time, name, n);
    item("BUS-RND");
    for (int r = 0; r < n; r++) round(r);
    $display("%0t: [%s] %0d CPU requests, %0d APB transfers", $time, name, sb.n_cpu, sb.n_apb);
  endtask

  function bit [31:0] rand_addr();
    bit [31:0] a;
    int k = $urandom_range(99);
    if (k < 40)      a = {18'd0, 12'($urandom), 2'b00};                                   // SRAM
    else if (k < 75) a = {16'h1000, 4'($urandom_range(5)), 10'($urandom), 2'b00};         // APB slots 0..5
    else if (k < 82) a = {16'h1000, 4'($urandom_range(15, 6)), 10'($urandom), 2'b00};     // disabled slots
    else if (k < 90) a = {16'h0000, 2'b01, 12'($urandom), 2'b00};                         // 0x4000..0x7FFF
    else if (k < 95) a = {16'h1001 + 16'($urandom_range(3)), 14'($urandom), 2'b00};       // just above APB
    else             a = {$urandom} & 32'hFFFF_FFFC;
    return a;
  endfunction

  task round(input int r);
    bit [31:0] a, rd, ra;
    bit        e;
    bit [1:0]  br, rr;
    int        n_req = $urandom_range(40, 10);
    bit [1:0]  codes[4] = '{OKAY, EXOKAY, SLVERR, DECERR};
    int        kind[$], k;
    for (int s = 0; s < 6; s++) begin
      pslv.wait_n[s] = ($urandom_range(3) == 0) ? $urandom_range(4) : 0;
      pslv.err_rd[s] = ($urandom_range(7) == 0);
      pslv.err_wr[s] = ($urandom_range(7) == 0);
    end
    aslv.resp = codes[$urandom_range(3)];
    $display("%0t: [%s] round %0d: %0d requests, wait states %0d %0d %0d %0d %0d %0d, master 2 resp %b",
             $time, name, r, n_req, pslv.wait_n[0], pslv.wait_n[1], pslv.wait_n[2], pslv.wait_n[3],
             pslv.wait_n[4], pslv.wait_n[5], aslv.resp);
    // kind of every request first: mem_req is kept high (back to back) only
    // when the next request is on the same CPU port, as a CPU would do
    for (int i = 0; i < n_req; i++) begin
      k = $urandom_range(9);
      kind.push_back(k < 7 ? 0 : (k < 9 ? 1 : 2));
    end
    kind.push_back(3);
    for (int i = 0; i < n_req; i++) begin
      bit keep = (kind[i + 1] == kind[i]) && kind[i] != 2 && $urandom_range(2) == 0;
      if (kind[i] == 0) begin
        a = rand_addr();
        cpu(0, $urandom_range(1), $urandom_range(5) == 0, a, $urandom, 4'($urandom_range(15, 1)), rd, e, keep);
      end else if (kind[i] == 1) begin
        a = {$urandom} & 32'hFFFF_FFFC;
        cpu(1, $urandom_range(1), $urandom_range(5) == 0, a, $urandom, 4'($urandom_range(15, 1)), rd, e, keep);
      end else begin
        a  = rand_addr();
        ra = rand_addr();
        direct(a, $urandom, ra, br, rr, rd);
      end
    end
    clks($urandom_range(3) + 1);
  endtask
endclass
