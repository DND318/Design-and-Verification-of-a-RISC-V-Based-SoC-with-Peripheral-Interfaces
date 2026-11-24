class fifo_base_test extends uvm_test;
  `uvm_component_utils(fifo_base_test)
  fifo_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = fifo_env::type_id::create("env", this);
  endfunction

  virtual function fifo_base_seq make_seq();
    return null;
  endfunction

  task run_phase(uvm_phase phase);
    fifo_base_seq seq = make_seq();
    phase.raise_objection(this);
    if (seq == null) `uvm_fatal("TEST", "no sequence")
    if (!seq.randomize()) `uvm_fatal("TEST", "sequence randomize failed")
    seq.start(env.agt.sqr);
    #50;
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server rs = uvm_report_server::get_server();
    if (rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL) == 0)
      `uvm_info("TEST", "TEST PASSED", UVM_NONE)
    else
      `uvm_info("TEST", "TEST FAILED", UVM_NONE)
  endfunction
endclass

class fifo_smoke_test extends fifo_base_test;
  `uvm_component_utils(fifo_smoke_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function fifo_base_seq make_seq();
    fifo_smoke_seq s = fifo_smoke_seq::type_id::create("s");
    return s;
  endfunction
endclass

class fifo_rand_test extends fifo_base_test;
  `uvm_component_utils(fifo_rand_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function fifo_base_seq make_seq();
    fifo_rand_seq s = fifo_rand_seq::type_id::create("s");
    return s;
  endfunction
endclass

class fifo_full_empty_test extends fifo_base_test;
  `uvm_component_utils(fifo_full_empty_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function fifo_base_seq make_seq();
    fifo_full_empty_seq s = fifo_full_empty_seq::type_id::create("s");
    return s;
  endfunction
endclass
