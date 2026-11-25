// One APB operation. The stimulus creates it, the driver executes it and
// fills the response fields; the monitor creates one for every clock edge
// that has something to report (a transfer, a reset, an irq change).
typedef enum int {APB_XFER, APB_IDLE, APB_SETUP_ONLY} apb_kind_e;

class apb_packet;
  // ---------------------------------------------------------------- request
  apb_kind_e        kind = APB_XFER;
  rand bit          write;
  rand bit [11:0]   addr;
  rand bit [31:0]   data;
  rand bit [3:0]    strb;
  rand int unsigned gap;        // extra idle clocks before SETUP
  int unsigned      n_idle;     // APB_IDLE: number of clocks to wait
  bit               b2b;        // SETUP right after the previous ACCESS (no idle clock)
  bit               pre_post;   // drive pre_data before SETUP and post_data after ACCESS
  bit [31:0]        pre_data;
  bit [31:0]        post_data;

  // Offsets a random packet may use (set by the test before randomize())
  bit [11:0]        addr_list[$];

  // ---------------------------------------------------------------- response / observation
  bit [31:0]        rdata;
  bit               pready;
  bit               pslverr;
  longint unsigned  cyc_sample;  // driver: cycle count when PRDATA was sampled
  longint unsigned  cyc_end;     // driver: number of the ACCESS edge
  // monitor only
  longint unsigned  edge_no;     // number of the clock edge (1 = first rising edge)
  bit               rst_n;
  bit               xfer;        // a transfer completed at this edge
  bit [7:0]         irq;

  // ---------------------------------------------------------------- constraints
  constraint c_addr { addr_list.size() > 0 -> addr inside {addr_list}; }
  constraint c_strb { strb dist {4'hF := 6, [4'h0:4'hE] :/ 4}; }
  constraint c_gap  { gap dist {0 := 5, [1:3] :/ 4, [4:20] :/ 1}; }

`ifdef VERILATOR
  // Constraint blocks are ignored by Verilator 5.020: apply the same rules by hand
  // so that a test runs on both simulators (XSim solves the constraints).
  // (Verilator 5.020 also leaves the rand members of a base class unchanged
  // when randomize() is called on a derived class, so all are set here.)
  function void post_randomize();
    write = 1'($urandom_range(1));
    data  = $urandom;
    if (addr_list.size() > 0) addr = addr_list[$urandom_range(addr_list.size() - 1)];
    strb = ($urandom_range(9) < 6) ? 4'hF : 4'($urandom_range(14));
    case ($urandom_range(9))
      0, 1, 2, 3, 4: gap = 0;
      5, 6, 7, 8:    gap = $urandom_range(3, 1);
      default:       gap = $urandom_range(20, 4);
    endcase
  endfunction
`endif

  function string sprint();
    case (kind)
      APB_IDLE:       return $sformatf("idle %0d clocks", n_idle);
      APB_SETUP_ONLY: return $sformatf("SETUP only %s addr=%h", write ? "write" : "read", addr);
      default:        return write ? $sformatf("write addr=%h data=%h strb=%b", addr, data, strb)
                                   : $sformatf("read  addr=%h data=%h", addr, rdata);
    endcase
  endfunction

  function void display(string comp);
    $display("%0t: [%s] %s", $time, comp, sprint());
  endfunction
endclass
