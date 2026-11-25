`timescale 1ns/1ps
// Behavioural model of the Microchip 24LC32A 32-Kbit (4096 x 8) I2C serial EEPROM,
// written from the datasheet (DS21713). Works from the resolved bus lines only
// (no clock); the bus is wired-AND with pull-ups outside this model.
//   - Control byte: 1010 A2 A1 A0 R/W; DEV_ADDR is the 7-bit address (0x50 = A2..A0 = 000).
//     A control byte for another address is not acknowledged; the device then waits
//     for the next START (standby).
//   - Write: control(W), address high byte (upper 4 bits don't care), address low
//     byte, then 1..32 data bytes. Data goes to a page buffer; the low 5 address bits
//     increment and wrap inside the 32-byte page. The write is started by STOP; a START
//     before STOP discards the data (address pointer is still set: dummy write).
//   - Internal write cycle: TWC_NS (short, scaled-down stand-in for tWC = 5 ms). During
//     it the device does not acknowledge its control byte (ACK polling).
//   - Current-address read: control(R), bytes from the internal address counter.
//   - Random read: dummy write of the address, repeated START, control(R).
//   - Sequential read: after a master ACK the next byte follows; the counter rolls
//     over from 0xFFF to 0x000. After a master NACK the device waits for STOP/START.
//   - The address counter points to the last byte accessed + 1.
//   - Inputs sampled on SCL rising edges, SDA output changes TAA_NS after SCL falls.
// Initial memory content: byte at address a = pattern(a) (see function below).
module i2c_eeprom_24lc32a #(
  parameter logic [6:0] DEV_ADDR = 7'h50,
  parameter int         TWC_NS   = 10000,
  parameter int         TAA_NS   = 40
) (
  input  wire  scl_i,
  input  wire  sda_i,
  output logic sda_drive_low_o
);

  localparam int ST_IDLE = 0;   // standby: wait for START
  localparam int ST_CTRL = 1;   // receiving the control byte
  localparam int ST_ADRH = 2;   // receiving the address high byte
  localparam int ST_ADRL = 3;   // receiving the address low byte
  localparam int ST_WDAT = 4;   // receiving data bytes
  localparam int ST_RDAT = 5;   // sending data bytes

  logic [7:0]  mem  [0:4095];
  logic [7:0]  pbuf [0:31];
  bit          pval [0:31];
  int          st = ST_IDLE;
  int          cnt = 0;           // SCL rising edges inside the current byte (1..9)
  logic [7:0]  shreg = 8'h00;
  logic [7:0]  txbyte = 8'h00;
  logic [11:0] ptr = 12'h000;     // internal address counter
  logic [11:0] waddr = 12'h000;   // write address (page + offset)
  bit          rw = 1'b0;
  bit          acked = 1'b0;
  bit          mack = 1'b0;       // master ACK sampled during a read
  int          nwr = 0;           // data bytes received in the current write
  time         wc_end = 0;        // end of the internal write cycle

  // Statistics, readable by a testbench through hierarchical names if wanted.
  int          n_write_cycles = 0;
  int          n_ctrl_nacked = 0;

  function automatic logic [7:0] pattern(input int a);
    return 8'((a * 37 + (a >> 8) * 11 + 5) & 255);
  endfunction

  initial begin
    sda_drive_low_o = 1'b0;
    for (int i = 0; i < 4096; i++) mem[i] = pattern(i);
    for (int i = 0; i < 32; i++) pval[i] = 1'b0;
  end

  task automatic drive(input bit low);
    #(TAA_NS);
    sda_drive_low_o = low;
  endtask

  // START: SDA falls while SCL is high. Uncommitted page data is discarded.
  always @(negedge sda_i) begin
    if (scl_i === 1'b1) begin
      st = ST_CTRL;
      cnt = 0;
      nwr = 0;
      for (int i = 0; i < 32; i++) pval[i] = 1'b0;
      sda_drive_low_o = 1'b0;
    end
  end

  // STOP: SDA rises while SCL is high. Starts the internal write cycle.
  always @(posedge sda_i) begin
    if (scl_i === 1'b1) begin
      if (st == ST_WDAT && nwr > 0) begin
        for (int i = 0; i < 32; i++)
          if (pval[i]) mem[{waddr[11:5], 5'(i)}] = pbuf[i];
        ptr = waddr;
        wc_end = $time + time'(TWC_NS);
        n_write_cycles++;
      end
      for (int i = 0; i < 32; i++) pval[i] = 1'b0;
      nwr = 0;
      st = ST_IDLE;
      cnt = 0;
      sda_drive_low_o = 1'b0;
    end
  end

  always @(posedge scl_i) begin
    if (st != ST_IDLE) begin
      cnt = cnt + 1;
      if (cnt <= 8) shreg = {shreg[6:0], (sda_i === 1'b0) ? 1'b0 : 1'b1};
      else if (st == ST_RDAT) mack = (sda_i === 1'b0);
    end
  end

  always @(negedge scl_i) begin
    if (st != ST_IDLE) begin
      if (cnt == 8) begin
        // End of the 8th bit: ACK the received byte, or release SDA for the master ACK.
        if (st == ST_RDAT) begin
          drive(1'b0);
        end else begin
          acked = 1'b1;
          case (st)
            ST_CTRL: begin
              if (shreg[7:1] != DEV_ADDR || $time < wc_end) begin
                acked = 1'b0;
                n_ctrl_nacked++;
              end else begin
                rw = shreg[0];
              end
            end
            ST_ADRH: waddr[11:8] = shreg[3:0];
            ST_ADRL: begin
              waddr[7:0] = shreg;
              ptr = waddr;
            end
            default: begin  // ST_WDAT
              pbuf[waddr[4:0]] = shreg;
              pval[waddr[4:0]] = 1'b1;
              waddr[4:0] = waddr[4:0] + 5'd1;
              nwr++;
            end
          endcase
          drive(acked);
        end
      end else if (cnt == 9) begin
        // End of the ACK clock.
        cnt = 0;
        case (st)
          ST_CTRL: begin
            if (!acked) begin
              st = ST_IDLE;
              drive(1'b0);
            end else if (rw) begin
              st = ST_RDAT;
              txbyte = mem[ptr];
              drive(~txbyte[7]);
            end else begin
              st = ST_ADRH;
              drive(1'b0);
            end
          end
          ST_ADRH: begin
            st = ST_ADRL;
            drive(1'b0);
          end
          ST_ADRL: begin
            st = ST_WDAT;
            drive(1'b0);
          end
          ST_WDAT: drive(1'b0);
          default: begin  // ST_RDAT
            ptr = ptr + 12'd1;
            if (mack) begin
              txbyte = mem[ptr];
              drive(~txbyte[7]);
            end else begin
              st = ST_IDLE;
              drive(1'b0);
            end
          end
        endcase
      end else if (st == ST_RDAT && cnt >= 1 && cnt <= 7) begin
        drive(~txbyte[7 - cnt]);
      end
    end
  end

endmodule
