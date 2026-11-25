// I2C packet
typedef enum int {I2C_SLAVE_CFG, I2C_EXT_START, I2C_EXT_STOP, I2C_START, I2C_STOP, I2C_BYTE} i2c_kind_e;

class i2c_packet;
  i2c_kind_e        kind = I2C_SLAVE_CFG;
  // SLAVE_CFG
  bit [6:0]         dev_addr = 7'h50;
  int unsigned      twc_ns = 10_000;     // internal write cycle (scaled down from 5 ms)
  int unsigned      taa_ns = 5;          // slave SDA change after SCL falls
  int unsigned      ext_ns = 500;        // EXT_*: time between the two line changes

  // filled by the monitor
  bit               rs;                  // START: repeated START
  bit               mid_byte;            // START / STOP inside a byte (not allowed)
  bit [7:0]         data;                // BYTE: data bits, MSB first
  bit               ack;                 // BYTE: 9th bit (0 = ACK, 1 = NACK)
  bit [7:0]         m_low, s_low;        // BYTE: data bits pulled low by the master / the slave
  bit               m_ack, s_ack;        // BYTE: ACK bit pulled low by the master / the slave
  bit               t_ok = 1;            // timing checks passed
  string            t_msg;

  // random traffic (rand test)
  rand bit [7:0]    rdata;

  function string sprint();
    case (kind)
      I2C_SLAVE_CFG: return $sformatf("slave cfg addr=%h twc=%0d ns taa=%0d ns", dev_addr, twc_ns, taa_ns);
      I2C_EXT_START: return "external START";
      I2C_EXT_STOP:  return "external STOP";
      I2C_START:     return $sformatf("%s%s%s", rs ? "repeated START" : "START", mid_byte ? " inside a byte" : "",
                                      t_ok ? "" : {" timing: ", t_msg});
      I2C_STOP:      return $sformatf("STOP%s%s", mid_byte ? " inside a byte" : "", t_ok ? "" : {" timing: ", t_msg});
      default:       return $sformatf("byte %h %s (master low %h/%b, slave low %h/%b)%s", data, ack ? "NACK" : "ACK",
                                      m_low, m_ack, s_low, s_ack, t_ok ? "" : {" timing: ", t_msg});
    endcase
  endfunction
endclass

// Settings of the DUT as programmed through APB (CTRL, PRESCALE). The
// scoreboard updates it from the APB writes it sees; the monitor reads the
// quarter period from it.
class i2c_cfg;
  bit          en;
  int unsigned prescale = 124;
  int unsigned clk_ns   = 20;           // clock period of the testbench
  function int unsigned q_ns();
    return (prescale + 1) * clk_ns;
  endfunction
endclass
