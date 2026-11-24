class fifo_base_seq extends uvm_sequence #(fifo_item);
  `uvm_object_utils(fifo_base_seq)

  function new(string name = "fifo_base_seq");
    super.new(name);
  endfunction

  // Send one cycle with fixed controls and random data.
  task send(bit wr, bit rd);
    fifo_item it = fifo_item::type_id::create("it");
    start_item(it);
    if (!it.randomize() with { wr == local::wr; rd == local::rd; })
      `uvm_fatal("SEQ", "randomize failed")
    finish_item(it);
  endtask
endclass

// Write 8 bytes, read them back, then idle.
class fifo_smoke_seq extends fifo_base_seq;
  `uvm_object_utils(fifo_smoke_seq)
  function new(string name = "fifo_smoke_seq");
    super.new(name);
  endfunction
  task body();
    repeat (8) send(1, 0);
    repeat (8) send(0, 1);
    repeat (4) send(0, 0);
  endtask
endclass

// Random traffic with a write/read mix that walks the FIFO level up and down.
class fifo_rand_seq extends fifo_base_seq;
  `uvm_object_utils(fifo_rand_seq)
  rand int unsigned n_items;
  constraint c_n { n_items inside {[500:2000]}; }
  function new(string name = "fifo_rand_seq");
    super.new(name);
  endfunction
  task body();
    fifo_item it;
    for (int unsigned i = 0; i < n_items; i++) begin
      int unsigned phase = (i / 64) % 3;
      it = fifo_item::type_id::create("it");
      start_item(it);
      if (!it.randomize() with {
            phase == 0 -> { wr dist {1 := 3, 0 := 1}; rd dist {1 := 1, 0 := 3}; }
            phase == 1 -> { wr dist {1 := 1, 0 := 3}; rd dist {1 := 3, 0 := 1}; }
          })
        `uvm_fatal("SEQ", "randomize failed")
      finish_item(it);
    end
  endtask
endclass

// Fill past full (overflow), drain past empty (underflow), then read+write at full.
class fifo_full_empty_seq extends fifo_base_seq;
  `uvm_object_utils(fifo_full_empty_seq)
  function new(string name = "fifo_full_empty_seq");
    super.new(name);
  endfunction
  task body();
    repeat (DEPTH + 3) send(1, 0);
    send(1, 1);
    repeat (DEPTH + 3) send(0, 1);
    send(1, 1);
    repeat (4) send(0, 0);
  endtask
endclass
