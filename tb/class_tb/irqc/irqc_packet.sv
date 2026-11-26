// IRQC packet
class irqc_packet;
  rand bit [3:0]    data;
  rand int unsigned hold;

  // filled by the monitor
  longint unsigned  edge_no;
  bit               rst_n;
  bit [3:0]         irq_in;
  bit               irq;

  constraint c_hold { hold dist {1 := 4, [2:5] :/ 4, [6:20] :/ 2}; }

`ifdef VERILATOR
  // (Verilator 5.020 ignores constraint blocks: same rules by hand)
  function void post_randomize();
    data = 4'($urandom);
    case ($urandom_range(9))
      0, 1, 2, 3: hold = 1;
      4, 5, 6, 7: hold = $urandom_range(5, 2);
      default:    hold = $urandom_range(20, 6);
    endcase
  endfunction
`endif

  function string sprint();
    return $sformatf("lines {gpio,i2c,spi,uart}=%b irq_meip=%b", irq_in, irq);
  endfunction
endclass
