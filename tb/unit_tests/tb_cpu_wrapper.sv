// Program-driven testbench for cpu_wrapper (RV32IM core).
// A behavioural memory with random wait states answers the shared memory
// port. The program (32-bit words, $readmemh) is loaded at address 0.
// Plusargs:
//   +HEX=<file>        program image (required)
//   +TOHOST=<hex>      address the program writes its result to:
//                      1 = pass, any other value = fail (riscv-tests style)
//   +MAXCYC=<n>        timeout in cycles (default 200000)
//   +WAIT=<n>          max random wait states per access (default 3)
//   +IRQ_AT=<n>        raise irq_mtip at cycle n (0 = never)
//   +EIRQ_AT=<n>       raise irq_meip at cycle n (0 = never)
// Test device: a store to IRQ_CLR_ADDR clears irq_mtip (bit 0) and/or
// irq_meip (bit 1). Accesses at or above MEM_BYTES (except the test device)
// return a bus error.
// Ends with "TEST PASSED" or "TEST FAILED" for scripts/check_log.sh.
`timescale 1ns/1ps
module tb_cpu_wrapper;

  localparam int unsigned MEM_BYTES    = 64 * 1024;
  localparam logic [31:0] IRQ_CLR_ADDR = 32'h0002_0000;

  logic        clk = 1'b0;
  logic        rst_n = 1'b0;

  logic        req, instr, we, ready, err;
  logic [3:0]  wstrb;
  logic [31:0] addr, wdata, rdata;
  logic        irq_mtip = 1'b0, irq_meip = 1'b0;

  logic [31:0] mem [MEM_BYTES/4];

  string       hex_file;
  logic [31:0] tohost;
  int unsigned max_cyc, max_wait, irq_at, eirq_at;
  int unsigned cycle = 0;
  int unsigned errors = 0;
  int unsigned n_fetch = 0, n_load = 0, n_store = 0;

  always #5 clk = ~clk;

  cpu_wrapper dut (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .mem_req_o   (req),
    .mem_instr_o (instr),
    .mem_we_o    (we),
    .mem_wstrb_o (wstrb),
    .mem_addr_o  (addr),
    .mem_wdata_o (wdata),
    .mem_rdata_i (rdata),
    .mem_ready_i (ready),
    .mem_err_i   (err),
    .irq_mtip_i  (irq_mtip),
    .irq_meip_i  (irq_meip)
  );

  // ---------------- memory model ----------------
  int unsigned wait_left = 0;
  logic        busy = 1'b0;

  function automatic logic in_mem(input logic [31:0] a);
    return a < MEM_BYTES;
  endfunction

  always @(posedge clk) begin
    ready <= 1'b0;
    err   <= 1'b0;
    rdata <= 32'hDEAD_BEEF;
    if (rst_n && req && !ready) begin
      if (!busy) begin
        busy      = 1'b1;
        wait_left = (max_wait == 0) ? 0 : $urandom_range(max_wait, 0);
      end
      if (wait_left == 0) begin
        busy  = 1'b0;
        ready <= 1'b1;
        if (we) begin
          n_store++;
          if (addr == IRQ_CLR_ADDR) begin
            if (wdata[0]) irq_mtip <= 1'b0;
            if (wdata[1]) irq_meip <= 1'b0;
          end else if (in_mem(addr)) begin
            for (int b = 0; b < 4; b++)
              if (wstrb[b]) mem[addr[15:2]][8*b +: 8] <= wdata[8*b +: 8];
            if (addr == tohost) begin
              if (wdata == 32'd1) begin
                $display("[%0t] tohost = 1 after %0d cycles (fetch %0d, load %0d, store %0d)",
                         $time, cycle, n_fetch, n_load, n_store);
                finish_test();
              end else begin
                $display("[%0t] ERROR: tohost = 0x%08h (failed test number %0d)",
                         $time, wdata, wdata >> 1);
                errors++;
                finish_test();
              end
            end
          end else begin
            err <= 1'b1;
          end
        end else begin
          if (instr) n_fetch++;
          else       n_load++;
          if (in_mem(addr)) rdata <= mem[addr[15:2]];
          else              err   <= 1'b1;
        end
      end else begin
        wait_left--;
      end
    end
  end

  // ---------------- interface checks ----------------
  logic        req_q = 1'b0, ready_q = 1'b0;
  logic        instr_q, we_q;
  logic [3:0]  wstrb_q;
  logic [31:0] addr_q, wdata_q;

  always @(posedge clk) begin
    if (rst_n) begin
      if (req_q && !ready_q) begin
        if (!req)
          begin errors++; $display("[%0t] ERROR: mem_req dropped before ready", $time); end
        else if (instr != instr_q || we != we_q || addr != addr_q ||
                 (we && (wstrb != wstrb_q || wdata != wdata_q)))
          begin errors++; $display("[%0t] ERROR: request changed while waiting", $time); end
      end
      if (req && instr && (we || addr[1:0] != 2'b00))
        begin errors++; $display("[%0t] ERROR: bad fetch addr=%08h we=%b", $time, addr, we); end
      if (req && we && wstrb == 4'b0000)
        begin errors++; $display("[%0t] ERROR: write with empty strobe", $time); end
    end
    req_q   <= req;
    ready_q <= ready;
    instr_q <= instr;
    we_q    <= we;
    wstrb_q <= wstrb;
    addr_q  <= addr;
    wdata_q <= wdata;
  end

  // ---------------- control ----------------
  task automatic finish_test();
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED");
    $finish;
  endtask

  always @(posedge clk) begin
    cycle <= cycle + 1;
    if (irq_at  != 0 && cycle == irq_at)  irq_mtip <= 1'b1;
    if (eirq_at != 0 && cycle == eirq_at) irq_meip <= 1'b1;
    if (cycle >= max_cyc) begin
      $display("[%0t] ERROR: timeout after %0d cycles, pc=%08h", $time, cycle, addr);
      errors++;
      finish_test();
    end
  end

  initial begin
    if (!$value$plusargs("HEX=%s", hex_file)) begin
      $display("ERROR: +HEX=<file> missing");
      $display("TEST FAILED");
      $finish;
    end
    if (!$value$plusargs("TOHOST=%h", tohost)) tohost = 32'hFFFF_FFFF;
    if (!$value$plusargs("MAXCYC=%d", max_cyc)) max_cyc = 200000;
    if (!$value$plusargs("WAIT=%d", max_wait)) max_wait = 3;
    if (!$value$plusargs("IRQ_AT=%d", irq_at)) irq_at = 0;
    if (!$value$plusargs("EIRQ_AT=%d", eirq_at)) eirq_at = 0;
    foreach (mem[i]) mem[i] = 32'h0000_0000;
    $readmemh(hex_file, mem);
    $display("program %s, tohost 0x%08h, wait 0..%0d", hex_file, tohost, max_wait);
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
  end

endmodule
