// Functional coverage. Simple bins only (XSim/xcrg rule in ADR 0001).
class fifo_coverage extends uvm_subscriber #(fifo_item);
  `uvm_component_utils(fifo_coverage)
  fifo_item t;

  covergroup cg_fifo;
    cp_wr: coverpoint t.wr { bins off = {0}; bins on = {1}; }
    cp_rd: coverpoint t.rd { bins off = {0}; bins on = {1}; }
    cx_op: cross cp_wr, cp_rd;
    cp_count: coverpoint t.count {
      bins empty = {0};
      bins one   = {1};
      bins mid   = {[2:DEPTH-2]};
      bins last  = {DEPTH-1};
      bins full  = {DEPTH};
    }
    cp_overflow:  coverpoint t.overflow  { bins hit = {1}; }
    cp_underflow: coverpoint t.underflow { bins hit = {1}; }
    cx_level_op: cross cp_count, cp_wr, cp_rd;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_fifo = new();
  endfunction

  function void write(fifo_item t);
    this.t = t;
    cg_fifo.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("cg_fifo coverage %0.2f%%", cg_fifo.get_coverage()), UVM_LOW)
  endfunction
endclass
