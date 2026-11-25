// UART packet
typedef enum int {UART_FRAME, UART_GLITCH, UART_SKEW,
                  UART_TX_START, UART_TX_FRAME, UART_RX_START, UART_RX_FRAME, UART_RX_FALSE} uart_kind_e;

class uart_packet;
  uart_kind_e       kind = UART_FRAME;
  rand bit [7:0]    data;
  rand bit [1:0]    par;          // 00 none, 01 even, 10 odd
  rand bit          stop2;
  rand int unsigned div;          // bit period = div + 1 clocks
  bit               bad_par;
  bit [1:0]         bad_stop;     // bit 0: first stop bit 0, bit 1: second stop bit 0
  int unsigned      glitch_clks;
  int               skew;

  // filled by the monitor
  longint unsigned  cyc;          // clock count at the start bit
  bit               perr;         // parity bit wrong for the decoder settings
  bit               ferr;         // a stop bit was 0
  bit               fmt_ok;       // TX: every bit stable for one bit period
  bit               pin_follow;   // TX: uart_tx_o equal to the transmitter output
  bit               pin_idle;     // TX: uart_tx_o stayed 1 (loopback)
  int unsigned      nbits;        // frame length in bits

  constraint c_par { par inside {2'b00, 2'b01, 2'b10}; }
  constraint c_div { div inside {[3:20]}; }

`ifdef VERILATOR
  // (Verilator 5.020 ignores constraint blocks: same rules by hand)
  function void post_randomize();
    par   = 2'($urandom_range(2));
    div   = $urandom_range(20, 3);
    stop2 = 1'($urandom_range(1));
    data  = 8'($urandom);
  endfunction
`endif

  function int unsigned frame_bits();
    return 10 + ((par != 2'b00) ? 1 : 0) + (stop2 ? 1 : 0);
  endfunction

  static function bit par_bit(bit [7:0] d, bit [1:0] p);
    // even: number of ones in data + parity is even; odd: it is odd
    return (p == 2'b10) ? ~(^d) : (^d);
  endfunction

  function string sprint();
    string pn = (par == 2'b01) ? "E" : (par == 2'b10) ? "O" : "N";
    case (kind)
      UART_GLITCH:   return $sformatf("glitch %0d clocks", glitch_clks);
      UART_SKEW:     return $sformatf("skewed frame %h div=%0d skew=%0d", data, div, skew);
      UART_TX_START: return $sformatf("TX start at cycle %0d", cyc);
      UART_RX_START: return $sformatf("RX start at cycle %0d", cyc);
      UART_RX_FALSE: return $sformatf("RX false start at cycle %0d", cyc);
      UART_TX_FRAME: return $sformatf("TX frame %h 8%s%0d div=%0d fmt_ok=%b", data, pn, stop2 + 1, div, fmt_ok);
      UART_RX_FRAME: return $sformatf("RX frame %h 8%s%0d div=%0d perr=%b ferr=%b", data, pn, stop2 + 1, div, perr, ferr);
      default:       return $sformatf("frame %h 8%s%0d div=%0d bad_par=%b bad_stop=%b",
                                      data, pn, stop2 + 1, div, bad_par, bad_stop);
    endcase
  endfunction
endclass

// Line settings of the DUT as programmed through APB (CTRL, BAUD). The
// scoreboard updates it from the APB writes it sees; the monitor reads it at
// every start bit to know how to decode the frame.
class uart_cfg;
  int unsigned div   = 433;
  bit [1:0]    par   = 2'b00;
  bit          stop2 = 1'b0;
  bit          tx_en, rx_en, loopback;
  int unsigned clk_ns = 20;          // clock period of the testbench
endclass
