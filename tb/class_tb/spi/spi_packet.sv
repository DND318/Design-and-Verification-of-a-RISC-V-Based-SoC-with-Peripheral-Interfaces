// SPI packet
typedef enum int {SPI_BYTE, SPI_START, SPI_FRAME} spi_kind_e;

class spi_packet;
  spi_kind_e        kind = SPI_BYTE;
  rand bit [7:0]    data;         // BYTE: slave byte

  // filled by the monitor
  bit [7:0]         mosi, miso;
  bit               cpol, cpha, lsb;
  int unsigned      div;
  bit               cs_n;         // CS level during the frame
  bit               first;        // no frame before it (since reset)
  longint unsigned  gap_ns;       // 16th edge of the previous frame -> 1st edge of this one
  bit               half_ok;      // every SCLK half period = (div + 1) clocks
  bit               setup_ok;     // MOSI stable >= half period before every sampling edge
  bit               hold_ok;      // MOSI stable >= half period after every sampling edge
  bit               cs_ok;        // CS did not change during the frame

  function string sprint();
    case (kind)
      SPI_START: return $sformatf("frame start mode %0d%s div=%0d cs_n=%b gap=%0d ns",
                                  {cpol, cpha}, lsb ? " LSB" : "", div, cs_n, gap_ns);
      SPI_FRAME: return $sformatf("frame mosi=%h miso=%h mode %0d%s div=%0d cs_n=%b half_ok=%b setup_ok=%b hold_ok=%b cs_ok=%b",
                                  mosi, miso, {cpol, cpha}, lsb ? " LSB" : "", div, cs_n,
                                  half_ok, setup_ok, hold_ok, cs_ok);
      default:   return $sformatf("slave byte %h", data);
    endcase
  endfunction
endclass

// Settings of the DUT as programmed through APB (CTRL, CLKDIV, CS). The
// scoreboard updates it from the APB writes it sees; the monitor and the
// slave model read it (mode, bit order, half period).
class spi_cfg;
  bit          en, cpol, cpha, lsb;
  int unsigned div    = 1;
  bit          cs     = 1'b1;
  int unsigned clk_ns = 20;         // clock period of the testbench
  int unsigned miso_dly = 3;        // slave: MISO changes this many ns after its shift edge
endclass
