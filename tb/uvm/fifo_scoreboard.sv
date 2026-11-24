// Reference model: a queue. Checks every observed output against it, then
// applies the cycle's push/pop.
class fifo_scoreboard extends uvm_subscriber #(fifo_item);
  `uvm_component_utils(fifo_scoreboard)
  bit [WIDTH-1:0] model[$];
  int unsigned    n_checked;
  int unsigned    n_errors;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void chk(bit ok, string what);
    n_checked++;
    if (!ok) begin
      n_errors++;
      `uvm_error("SCB", what)
    end
  endfunction

  function void write(fifo_item t);
    int unsigned sz = model.size();
    chk(t.empty == (sz == 0), $sformatf("empty=%0b, model size %0d", t.empty, sz));
    chk(t.full == (sz == DEPTH), $sformatf("full=%0b, model size %0d", t.full, sz));
    chk(t.count == sz, $sformatf("count=%0d, model size %0d", t.count, sz));
    chk(t.overflow == (t.wr && sz == DEPTH), "overflow mismatch");
    chk(t.underflow == (t.rd && sz == 0), "underflow mismatch");
    if (sz != 0)
      chk(t.rdata == model[0], $sformatf("rdata=%02h, expected %02h", t.rdata, model[0]));
    if (t.rd && sz > 0) void'(model.pop_front());
    if (t.wr && sz < DEPTH) model.push_back(t.data);
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB", $sformatf("checked %0d, errors %0d", n_checked, n_errors), UVM_LOW)
  endfunction
endclass
