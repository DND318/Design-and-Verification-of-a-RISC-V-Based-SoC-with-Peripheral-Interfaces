// GPIO packet
class gpio_packet;
  rand bit [7:0]    data;         // driver: value for gpio_i
  rand int unsigned hold;         // driver: clocks to hold it

  // filled by the monitor
  longint unsigned  edge_no;
  bit               rst_n;
  bit [7:0]         gpio_i;
  bit [7:0]         gpio_o;
  bit [7:0]         gpio_oe;
  bit               irq;

  constraint c_hold { hold dist {1 := 3, [2:4] :/ 4, [5:20] :/ 3}; }

`ifdef VERILATOR
  // (Verilator 5.020 ignores constraint blocks: same rules by hand)
  function void post_randomize();
    data = 8'($urandom);
    case ($urandom_range(9))
      0, 1, 2:    hold = 1;
      3, 4, 5, 6: hold = $urandom_range(4, 2);
      default:    hold = $urandom_range(20, 5);
    endcase
  endfunction
`endif

  function string sprint();
    return $sformatf("gpio_i=%h gpio_o=%h gpio_oe=%h irq=%b", gpio_i, gpio_o, gpio_oe, irq);
  endfunction
endclass
