class fifo_driver extends uvm_driver #(fifo_item);
  `uvm_component_utils(fifo_driver)
  virtual fifo_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual fifo_if not set")
  endfunction

  task run_phase(uvm_phase phase);
    vif.wr_en <= 1'b0;
    vif.rd_en <= 1'b0;
    vif.wdata <= '0;
    wait (vif.rst_n === 1'b1);
    // One item per clock. With no item pending the bus idles.
    forever begin
      @(vif.drv_cb);
      seq_item_port.try_next_item(req);
      if (req != null) begin
        vif.drv_cb.wr_en <= req.wr;
        vif.drv_cb.rd_en <= req.rd;
        vif.drv_cb.wdata <= req.data;
        seq_item_port.item_done();
      end else begin
        vif.drv_cb.wr_en <= 1'b0;
        vif.drv_cb.rd_en <= 1'b0;
      end
    end
  endtask
endclass
