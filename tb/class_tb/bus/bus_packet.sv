// Bus packet
typedef enum int {BUS_CPU, BUS_AXI, BUS_AXI_WR, BUS_AXI_RD, BUS_APB} bus_kind_e;

class bus_packet;
  bus_kind_e        kind = BUS_CPU;
  int               port;            // CPU / AXI_*: port number (see above)
  rand bit          we;
  bit               instr;
  rand bit [31:0]   addr;
  rand bit [31:0]   wdata;
  rand bit [3:0]    wstrb;
  bit               keep;            // CPU: keep mem_req high for the next request (back to back)
  bit               direct;          // AXI_* port 0: made by the direct AXI port, not by the master adapter
  // BUS_AXI: write and read in the same cycle
  bit               do_wr, do_rd;
  bit [31:0]        raddr;
  // results / monitor fields
  bit [31:0]        rdata;
  bit               err;             // CPU: mem_err
  int               n_ready;         // CPU: mem_ready pulses seen for this request
  bit [1:0]         resp, bresp, rresp;
  bit [2:0]         prot;
  int               slot;            // APB: PSEL index
  int               waits;           // APB: ACCESS cycles with PREADY = 0
  bit               pslverr;
  longint unsigned  cyc;             // clock count at the end

  constraint c_strb { wstrb != 4'h0; }

  function string sprint();
    case (kind)
      BUS_AXI_WR: return $sformatf("AXI port %0d write %h = %h strb %b prot %b -> BRESP %b", port, addr, wdata, wstrb, prot, resp);
      BUS_AXI_RD: return $sformatf("AXI port %0d read %h prot %b -> %h RRESP %b", port, addr, prot, rdata, resp);
      BUS_APB:    return $sformatf("APB slot %0d %s %h %s strb %b prot %b waits %0d pslverr %b",
                                   slot, we ? "write" : "read", addr, we ? $sformatf("= %h", wdata) : $sformatf("-> %h", rdata),
                                   wstrb, prot, waits, pslverr);
      BUS_AXI:    return $sformatf("direct AXI%s%s", do_wr ? $sformatf(" write %h = %h", addr, wdata) : "",
                                   do_rd ? $sformatf(" read %h", raddr) : "");
      default:    return $sformatf("CPU port %0d %s%s %h%s", port, instr ? "fetch " : "", we ? "write" : "read", addr,
                                   we ? $sformatf(" = %h strb %b", wdata, wstrb) : "");
    endcase
  endfunction
endclass
