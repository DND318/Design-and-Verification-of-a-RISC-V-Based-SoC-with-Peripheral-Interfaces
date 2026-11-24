// One clock cycle of FIFO traffic. The driver uses wr/rd/data; the monitor
// also fills the observed outputs.
class fifo_item extends uvm_sequence_item;
  rand bit             wr;
  rand bit             rd;
  rand bit [WIDTH-1:0] data;

  bit [WIDTH-1:0]       rdata;
  bit                   full;
  bit                   empty;
  bit [$clog2(DEPTH):0] count;
  bit                   overflow;
  bit                   underflow;

  `uvm_object_utils_begin(fifo_item)
    `uvm_field_int(wr, UVM_DEFAULT)
    `uvm_field_int(rd, UVM_DEFAULT)
    `uvm_field_int(data, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(rdata, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(full, UVM_DEFAULT)
    `uvm_field_int(empty, UVM_DEFAULT)
    `uvm_field_int(count, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(overflow, UVM_DEFAULT)
    `uvm_field_int(underflow, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "fifo_item");
    super.new(name);
  endfunction
endclass
