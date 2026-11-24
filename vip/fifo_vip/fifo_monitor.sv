// Samples every clock after reset and publishes one fifo_item per cycle.
class fifo_monitor extends uvm_monitor;
  `uvm_component_utils(fifo_monitor)
  virtual fifo_if vif;
  uvm_analysis_port #(fifo_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual fifo_if not set")
  endfunction

  task run_phase(uvm_phase phase);
    fifo_item it;
    forever begin
      @(vif.mon_cb);
      if (vif.rst_n !== 1'b1) continue;
      it = fifo_item::type_id::create("it");
      it.wr        = vif.mon_cb.wr_en;
      it.rd        = vif.mon_cb.rd_en;
      it.data      = vif.mon_cb.wdata;
      it.rdata     = vif.mon_cb.rdata;
      it.full      = vif.mon_cb.full;
      it.empty     = vif.mon_cb.empty;
      it.count     = vif.mon_cb.count;
      it.overflow  = vif.mon_cb.overflow;
      it.underflow = vif.mon_cb.underflow;
      ap.write(it);
    end
  endtask
endclass
