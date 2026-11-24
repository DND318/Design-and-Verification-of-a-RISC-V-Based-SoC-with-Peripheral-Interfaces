"""Verification plan (vplan) of the RISC-V SoC.

Writes doc/vplan/soc_vplan.xlsx in the format of the register checklist
template (columns ID .. PIC), one sheet per block plus a README sheet.

Register items (reset value, R/W access, read-only, reserved offsets) are
generated from doc/spec/regmap.py, so they follow the spec automatically.
Function items are written by hand below, each traced to a spec section.

Usage: python3 gen_vplan.py        (needs openpyxl)
"""

import os
import sys

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "spec"))
import regmap  # noqa: E402

PIC = "Ngoc"
METHOD = "Directed"

# Planned dates per sheet (start, end), dd/mm/yyyy
PLAN = {
    "UART": ("16/11/2026", "17/11/2026"),
    "SPI": ("18/11/2026", "19/11/2026"),
    "BUS": ("20/11/2026", "21/11/2026"),
    "TIMER": ("22/11/2026", "22/11/2026"),
    "IRQC": ("23/11/2026", "23/11/2026"),
    "GPIO": ("23/11/2026", "23/11/2026"),
    "I2C": ("24/11/2026", "25/11/2026"),
    "SOC": ("26/11/2026", "27/11/2026"),
}

# Testbench that will run the items of each sheet
TB = {
    "UART": "tb_uart_apb", "SPI": "tb_spi_apb", "I2C": "tb_i2c_apb",
    "TIMER": "tb_timer_apb", "IRQC": "tb_irqc_apb", "GPIO": "tb_gpio_apb",
    "BUS": "tb_bus_sys", "SOC": "tb_soc_top / tb_cpu_wrapper / tb_cpu_axi",
}

PATTERNS = [0x00000000, 0xFFFFFFFF, 0x55555555, 0xAAAAAAAA]


# ---------------------------------------------------------------- helpers
def bit_range(bits):
    if ":" in bits:
        hi, lo = bits.split(":")
        return int(hi), int(lo)
    return int(bits), int(bits)


def mask_of(reg, types):
    m = 0
    for f in reg.fields:
        if f.type in types:
            hi, lo = bit_range(f.bits)
            m |= ((1 << (hi - lo + 1)) - 1) << lo
    return m


def reset_of(reg):
    v = 0
    for f in reg.fields:
        if f.type != "-":
            _, lo = bit_range(f.bits)
            v |= f.reset << lo
    return v


def h32(v):
    s = "%08X" % v
    return "32'h%s_%s" % (s[:4], s[4:])


class Sheet:
    def __init__(self, name, title, spec_ref):
        self.name, self.title, self.spec_ref = name, title, spec_ref
        self.rows = []
        self.sv = []          # SystemVerilog calls of the generated register items
        self.snap = []        # register offsets, for the reserved-access check
        self.rwregs = []      # (name, offset, rw mask, reset) of registers with RW bits

    def add(self, item, sub1, sub2, cls, seq, passc, formal=""):
        self.rows.append([item, sub1, sub2, METHOD, cls, seq, formal, passc])
        return "%s-%02d" % (self.name, len(self.rows))


# Notes for R/W pattern items where the spec defines a special case
RW_NOTES = {
    ("uart", "CTRL"): "parity = 2'b11 is prohibited: the field keeps its previous value "
                      "(pattern FFFF_FFFF reads back parity = 2'b00, the value written before it).",
    ("timer", "TCR"): "div_val 9..15 is prohibited: the field keeps its previous value "
                      "(FFFF_FFFF and AAAA_AAAA leave div_val unchanged). Write 0 before each pattern "
                      "so div_val never changes while timer_en = 1; write 0 at the end to stop the counter.",
}

RESET_NOTES = {
    ("gpio", "GPIO_IN"): "with gpio_i = 8'h00 during and after reset",
    ("timer", "TDR0"): "read before timer_en is set",
}


def expected_rw(block, reg, writes):
    """Expected read-back value after each write of the R/W item."""
    rw = mask_of(reg, ("RW",))
    cur = reset_of(reg)
    out = []
    for w in writes:
        new = (cur & ~rw) | (w & rw)
        if (block, reg.name) == ("uart", "CTRL") and (w >> 2) & 3 == 3:
            new = (new & ~0xC) | (cur & 0xC)            # prohibited parity keeps old value
        if (block, reg.name) == ("timer", "TCR") and (w >> 8) & 0xF > 8:
            new = (new & ~0xF00) | (cur & 0xF00)        # prohibited div_val keeps old value
        cur = new
        out.append(new)
    return out


def rw_writes(block, reg):
    if (block, reg.name) == ("timer", "TCR"):            # never change div_val while counting
        ws = []
        for p in PATTERNS:
            ws += [0, p]
        return ws + [0]
    return list(PATTERNS)


def sv_hex(v):
    return "32'h%08X" % (v & 0xFFFFFFFF)


def register_items(sh, block, regs):
    base = {b: base for b, _, base, _ in regmap.BLOCKS}[block]
    sh_base = "0x%08X" % base
    sv_reset, sv_other = [], []
    for r in regs:
        off = "0x%02X" % r.offset
        a12 = "12'h%03X" % r.offset
        rw = mask_of(r, ("RW",))
        ro_only = all(f.type in ("RO", "-") for f in r.fields)
        wo = any(f.type == "WO" for f in r.fields)
        note = RESET_NOTES.get((block, r.name), "")
        i = sh.add("Register access" if not sh.rows else "",
                   "%s (offset %s)" % (r.name, off), "Reset value check", "Basic",
                   "After reset is released, read %s (address %s + %s)%s." %
                   (r.name, sh_base, off, (", " + note) if note else ""),
                   "Read value = %s" % h32(reset_of(r)))
        sv_reset.append('reg_reset("%s", %s, %s);   // %s' % (i, a12, sv_hex(reset_of(r)), r.name))
        sh.snap.append(a12)
        if rw:
            seq = "\n".join("%d. Write %s & read back and compare" % (k + 1, h32(p)[4:])
                            for k, p in enumerate(PATTERNS))
            extra = RW_NOTES.get((block, r.name))
            passc = "Read value = write value AND %s (RW bits; reserved and RO bits read as their own value)" % h32(rw)
            if extra:
                passc += "\nException: " + extra
            i = sh.add("", "", "R/W access", "Basic", seq, passc)
            ws = rw_writes(block, r)
            for w, e in zip(ws, expected_rw(block, r, ws)):
                sv_other.append('reg_wr_exp("%s", %s, %s, %s);   // %s' % (i, a12, sv_hex(w), sv_hex(e), r.name))
            sv_other.append('wr(%s, %s);   // restore reset value' % (a12, sv_hex(reset_of(r))))
            sh.rwregs.append((r.name, r.offset, rw, reset_of(r)))
        elif ro_only:
            i = sh.add("", "", "Write ignored (RO)", "Basic",
                       "1. Read %s\n2. Write FFFF_FFFF, then 0000_0000\n3. Read %s again" % (r.name, r.name),
                       "Value in step 3 = value in step 1 (no field changes because of the write)")
            sv_other.append('reg_ro("%s", %s);   // %s' % (i, a12, r.name))
        elif wo:
            i = sh.add("", "", "Read value (WO)", "Basic",
                       "Read %s" % r.name, "Read value = 32'h0000_0000")
            sv_other.append('reg_wo("%s", %s);   // %s' % (i, a12, r.name))

    used = set(r.offset for r in regs)
    last = max(used)
    gaps = [o for o in range(0, last, 4) if o not in used]
    first_res = last + 4
    mid = (first_res + 0xFFC) // 2 & ~3
    offs = gaps + [first_res, mid, 0xFFC]
    names = ["offset 0x%03X%s" % (o, " (gap in the map)" if o in gaps else "") for o in offs]
    seq = "\n".join("%d. Write FFFF_FFFF to %s and read back" % (k + 1, n) for k, n in enumerate(names))
    seq += "\n%d. Read every register again" % (len(offs) + 1)
    i = sh.add("Reserved access", "", "", "Basic", seq,
               "1-%d. Read value = 32'h0000_0000, PSLVERR = 0\n"
               "%d. No register value changed" % (len(offs), len(offs) + 1))
    sv_other.append('res_snap();')
    for o in offs:
        sv_other.append('res_access("%s", 12\'h%03X);' % (i, o))
    sv_other.append('res_compare("%s");' % i)
    sh.sv += ["// reset values first, before any write"] + sv_reset + [""] + sv_other


D0, D1, D2 = 0xDEADBEEF, 0x12345678, 0xCAFEF00D


def apb_timing_items(sh, reg_a, off_a, reg_b, off_b):
    ra = [r for r in sh.rwregs if r[0] == reg_a][0]
    rb = [r for r in sh.rwregs if r[0] == reg_b][0]
    A, B = "12'h%03X" % ra[1], "12'h%03X" % rb[1]
    i = sh.add("Timing check", "Write", "Single write", "Basic",
               "APB write to %s: SETUP (PSEL=1, PENABLE=0) then ACCESS (PENABLE=1) with "
               "PWDATA = D1; drive PWDATA = D0 before and D2 after the transfer.\nRead back %s." % (reg_a, reg_a),
               "Read value = D1 (masked by the RW bits); PREADY = 1 in ACCESS; PSLVERR = 0")
    sh.sv.append('t_single_write("%s", %s, %s, %s, %s, %s);   // %s' %
                 (i, A, sv_hex(D0), sv_hex(D1), sv_hex(D2), sv_hex(ra[2]), reg_a))
    if reg_b == reg_a:
        i = sh.add("", "", "Continuous write", "Basic",
                   "Two APB writes to %s (%s) with no idle cycle between them: D1, then D2. Read back." % (reg_a, off_a),
                   "%s = D2 (masked by the RW bits)" % reg_a)
    else:
        i = sh.add("", "", "Continuous write", "Basic",
                   "Two APB writes with no idle cycle between them: %s (%s) = D1, then %s (%s) = D2.\n"
                   "Read back both." % (reg_a, off_a, reg_b, off_b),
                   "%s = D1, %s = D2 (masked by the RW bits)" % (reg_a, reg_b))
    sh.sv.append('t_cont_write("%s", %s, %s, %s, %s, %s, %s);' %
                 (i, A, B, sv_hex(D1), sv_hex(D2), sv_hex(ra[2]), sv_hex(rb[2])))
    i = sh.add("", "Read", "Single read", "Basic",
               "%s holds a non-reset value. One APB read; check PRDATA in the ACCESS cycle." % reg_a,
               "PRDATA = %s value when PENABLE = 1" % reg_a)
    sh.sv.append('t_single_read("%s", %s, %s, %s);' % (i, A, sv_hex(D2 if reg_a == reg_b else D1), sv_hex(ra[2])))
    if reg_b == reg_a:
        i = sh.add("", "", "Continuous read", "Basic",
                   "Two APB reads of %s with no idle cycle" % reg_a,
                   "Both PRDATA = %s value" % reg_a)
    else:
        i = sh.add("", "", "Continuous read", "Basic",
                   "%s and %s hold different values. Two APB reads with no idle cycle: %s then %s." %
                   (reg_a, reg_b, reg_b, reg_a),
                   "First PRDATA = %s value, second PRDATA = %s value" % (reg_b, reg_a))
    sh.sv.append('t_cont_read("%s", %s, %s, %s, %s, %s, %s);' %
                 (i, B, A, sv_hex(D2), sv_hex(D1 if reg_b != reg_a else D2), sv_hex(rb[2]), sv_hex(ra[2])))
    i = sh.add("", "Byte strobe", "PSTRB", "Basic",
               "Write %s = FFFF_FFFF, then write 0000_0000 with PSTRB = 4'b0001, 4'b0010, 4'b0100, 4'b1000 "
               "in turn, reading back after each write." % reg_a,
               "Only the byte lane with PSTRB = 1 changes to 0 each time (RW bits only)")
    sh.sv.append('t_pstrb("%s", %s, %s);' % (i, A, sv_hex(ra[2])))
    for name, off, rw, rst in sh.rwregs:
        if name in (reg_a, reg_b):
            sh.sv.append("wr(12'h%03X, %s);   // restore %s" % (off, sv_hex(rst), name))


# ---------------------------------------------------------------- sheets
def uart_sheet():
    sh = Sheet("UART", "UART (APB slot 0, base 0x1000_0000)", "Spec sec. UART; regmap UART")
    regs = dict((b, r) for b, _, _, r in regmap.BLOCKS)["uart"]
    register_items(sh, "uart", regs)
    apb_timing_items(sh, "BAUD", "0x04", "IER", "0x14")
    a = sh.add
    a("Side effects", "TXDATA", "PSTRB[0] = 0", "Corner",
      "With tx_en = 0, write TXDATA with PSTRB = 4'b1110, then read STATUS",
      "STATUS.tx_empty = 1 (nothing pushed)")
    a("", "RXDATA", "SETUP without ACCESS", "Corner",
      "Receive 1 byte. Drive PSEL = 1, PENABLE = 0 at RXDATA for 1 cycle and drop PSEL; then do a full read",
      "Full read returns the byte; STATUS.rx_empty = 1 only after the full read")
    a("", "RXDATA", "Read when empty", "Corner",
      "With RX FIFO empty, read RXDATA twice, then receive 1 byte and read it",
      "Empty reads return 0; the received byte is read correctly (FIFO not corrupted)")
    a("TX", "Frame format", "8N1, default baud", "Basic",
      "CTRL.tx_en = 1, BAUD = 433. Write 0x55, then 0xA6. Decode uart_tx_o with a line monitor.",
      "Each frame: start bit 0, 8 data bits LSB first, 1 stop bit 1, line idle = 1; "
      "every bit lasts BAUD+1 = 434 clocks; bytes 0x55, 0xA6 in order")
    a("", "Bit period", "baud_div = 3, 15, 1000", "Basic",
      "For each baud_div send 1 byte and measure each bit with the monitor",
      "Every bit lasts exactly baud_div + 1 clocks")
    a("", "Parity", "Even / odd", "Basic",
      "parity = 01 (even), send 0x07 and 0x03; parity = 10 (odd), send 0x07 and 0x03",
      "Parity bit after data: even -> 1, 0; odd -> 0, 1")
    a("", "Stop bits", "stop2 = 1", "Basic",
      "stop2 = 1, send 2 bytes back to back",
      "Each frame has 2 stop bits of 1; next start bit begins after the second stop bit")
    a("", "FIFO", "Burst of 16", "Basic",
      "tx_en = 0, write 16 bytes (0..15). Check STATUS.tx_full = 1. Set tx_en = 1.",
      "16 frames sent in order 0..15; STATUS.tx_empty = 1 and tx_busy = 0 at the end")
    a("", "FIFO", "Overflow", "Corner",
      "tx_en = 0, write 17 bytes, then tx_en = 1",
      "ISR.tx_ovf = 1 after the 17th write; exactly the first 16 bytes are sent")
    a("", "Enable", "tx_en = 0 holds data", "Basic",
      "tx_en = 0, write 2 bytes, wait 3 frame times, then tx_en = 1",
      "No activity on uart_tx_o while tx_en = 0; both bytes sent after enabling")
    a("", "Status", "tx_busy / tx_empty", "Basic",
      "Send 1 byte, poll STATUS during and after the frame",
      "tx_empty = 0 only while the byte is in the FIFO; tx_busy = 1 during the frame, 0 after the stop bit")
    a("RX", "Frame format", "8N1, default baud", "Basic",
      "CTRL.rx_en = 1. TB drives frames 0x55, 0xA6, 0x00, 0xFF on uart_rx_i at BAUD = 433.",
      "RXDATA returns the 4 bytes in order; no ISR error flag")
    a("", "Parity", "Even / odd, correct", "Basic",
      "parity = 01, then 10; TB sends bytes with the correct parity bit",
      "Bytes received; ISR.parity_err = 0")
    a("", "Parity", "Parity error", "Error",
      "parity = 01; TB sends a byte with the wrong parity bit",
      "ISR.parity_err = 1; byte still stored in RX FIFO (spec Proposed)")
    a("", "Stop bit", "Framing error", "Error",
      "TB sends a frame whose stop bit is 0, then a good frame",
      "ISR.frame_err = 1 for the bad frame; the next frame is received correctly")
    a("", "Stop bit", "stop2 = 1, second stop bit 0", "Error",
      "stop2 = 1; TB sends a frame with stop bits 1, 0",
      "ISR.frame_err = 1 (both stop bits are checked when stop2 = 1)")
    a("", "Start bit", "False start (glitch)", "Corner",
      "baud_div = 15. TB pulls uart_rx_i low for 1 clock, then for 5 clocks (< half bit), then idle",
      "No byte received; RX FIFO stays empty; no error flag")
    a("", "Sampling", "Mid-bit sampling", "Corner",
      "baud_div = 15. TB sends a byte with every bit edge moved by +4 and -4 clocks (quarter bit)",
      "Byte received correctly (bits are sampled at mid-bit)")
    a("", "FIFO", "Full and overrun", "Corner",
      "rx_en = 1, TB sends 17 bytes without software reading RXDATA",
      "STATUS.rx_full = 1 after 16; ISR.overrun = 1 after the 17th; reading gives the first 16 bytes in order")
    a("", "Enable", "rx_en = 0", "Basic",
      "rx_en = 0, TB sends 2 bytes",
      "RX FIFO stays empty; no ISR flag")
    a("", "Status", "rx_busy / rx_empty", "Basic",
      "TB sends 1 byte; poll STATUS during and after the frame",
      "rx_busy = 1 during the frame; rx_empty goes 0 after the stop bit")
    a("Loopback", "", "", "Basic",
      "CTRL = loopback | tx_en | rx_en. Write 0x3C to TXDATA. At the same time TB drives an external frame 0x81 on uart_rx_i.",
      "RXDATA = 0x3C; uart_tx_o stays 1 during the whole test; the external frame is not received")
    a("Interrupt", "Gating", "IER x ISR", "Basic",
      "For each ISR bit (tx_empty, rx_ne, parity_err, frame_err, overrun, tx_ovf): make the flag 1, "
      "check irq_uart_o with its IER bit 0 and then 1",
      "irq_uart_o = OR(ISR AND IER): 0 while the IER bit is 0, 1 when it is 1")
    a("", "Clear", "W1C", "Basic",
      "Set parity_err, frame_err, overrun, tx_ovf. Write ISR = 0 (PSTRB all 1); write ISR = FFFF_FFFF with PSTRB = 4'b1110; "
      "then write 1 to one bit at a time with PSTRB[0] = 1",
      "Flags unchanged by the first two writes; each later write clears only its own bit")
    a("", "Clear", "Level flags", "Basic",
      "Receive 1 byte with rx_ne_ie = 1, then read RXDATA",
      "ISR.rx_ne and irq_uart_o go 0 after the read; writing 1 to ISR bit 1 or 0 has no effect")
    return sh


def spi_sheet():
    sh = Sheet("SPI", "SPI master (APB slot 1, base 0x1000_1000)", "Spec sec. SPI master; regmap SPI")
    regs = dict((b, r) for b, _, _, r in regmap.BLOCKS)["spi"]
    register_items(sh, "spi", regs)
    apb_timing_items(sh, "CLKDIV", "0x04", "IER", "0x18")
    a = sh.add
    a("Side effects", "TXDATA", "PSTRB[0] = 0", "Corner",
      "spi_en = 0, write TXDATA with PSTRB = 4'b1110, read STATUS",
      "STATUS.tx_empty = 1 (nothing pushed)")
    a("", "RXDATA", "Read when empty", "Corner",
      "With RX FIFO empty, read RXDATA, then do 1 transfer and read it",
      "Empty read returns 0; the transfer's byte is read correctly")
    a("Transfer", "Mode 0..3", "MSB first", "Basic",
      "CS = 0. For each (cpol, cpha) send 0xA5 and 0x3C; slave model returns 0x5A and 0xC3 on MISO.",
      "MOSI bits match TXDATA MSB first; RXDATA = slave bytes; SCLK idles at CPOL; "
      "CPHA = 0 samples on the 1st edge, CPHA = 1 on the 2nd edge of each bit")
    a("", "Mode 0..3", "LSB first", "Basic",
      "Same as above with lsb_first = 1",
      "Bits sent and received LSB first in all 4 modes")
    a("", "Clock", "clk_div = 0, 1, 12, 255", "Basic",
      "Send 1 byte for each clk_div and measure SCLK",
      "SCLK period = 2 x (clk_div + 1) clocks; exactly 8 SCLK cycles per byte")
    a("", "Data timing", "MOSI setup / hold", "Corner",
      "Mode 0..3, clk_div = 0 and 3. Monitor checks MOSI at every SCLK edge",
      "MOSI never changes on a sampling edge; it is stable for at least one half SCLK period before it")
    a("", "Data timing", "MISO sampling at clk_div = 0", "Corner",
      "clk_div = 0, all modes. Slave model changes MISO right after its shift edge (+15 ns)",
      "RXDATA = slave bytes in every mode (MISO taken at the sampling edge)")
    a("", "Burst", "Back to back", "Basic",
      "Write 4 bytes into TX FIFO, then spi_en = 1",
      "4 frames in order; STATUS.busy stays 1 between them; CS_N not changed by hardware; 4 bytes in RX FIFO")
    a("", "Enable", "spi_en = 0", "Basic",
      "spi_en = 0, write 2 bytes, wait, then spi_en = 1",
      "No SCLK edge while spi_en = 0; 2 frames after enabling")
    a("", "Enable", "spi_en cleared mid-burst", "Corner",
      "Write 4 bytes, spi_en = 1, clear spi_en during byte 2",
      "Byte 2 completes; bytes 3 and 4 wait in TX FIFO and go out after spi_en = 1 again")
    a("Chip select", "", "", "Basic",
      "Write CS = 0, then 1; check spi_cs_no; run a transfer with CS = 1",
      "spi_cs_no follows CS.cs_n directly; reset value 1")
    a("FIFO", "TX", "Overflow", "Corner",
      "spi_en = 0, write 17 bytes, then spi_en = 1",
      "STATUS.tx_full = 1 after 16 writes; exactly 16 bytes transferred")
    a("", "RX", "Full and overrun", "Corner",
      "Do 17 transfers without reading RXDATA",
      "STATUS.rx_full = 1 after 16; ISR.rx_ovr = 1; reading gives the first 16 bytes in order")
    a("Status", "busy", "", "Basic",
      "Poll STATUS.busy before, during and after a byte",
      "busy = 1 only while a byte is being shifted")
    a("Interrupt", "done", "Single and burst", "Basic",
      "done_ie = 1. Send 1 byte; clear; send a burst of 3",
      "ISR.done = 1 after the single byte; in the burst done is set only after the last byte (TX FIFO empty)")
    a("", "Gating", "IER x ISR", "Basic",
      "Make done and rx_ovr 1; test irq_spi_o with each IER combination",
      "irq_spi_o = OR(ISR AND IER)")
    a("", "Clear", "W1C", "Basic",
      "Write ISR = 0; write ISR = 3 with PSTRB = 4'b1110; then write 1 to each bit with PSTRB[0] = 1",
      "First two writes change nothing; each later write clears only its own bit")
    return sh


def i2c_sheet():
    sh = Sheet("I2C", "I2C master (*) (APB slot 2, base 0x1000_2000)", "Spec sec. I2C master; regmap I2C")
    regs = dict((b, r) for b, _, _, r in regmap.BLOCKS)["i2c"]
    register_items(sh, "i2c", regs)
    apb_timing_items(sh, "PRESCALE", "0x04", "TXDATA", "0x0C")
    a = sh.add
    a("Bus timing", "SCL", "Frequency", "Basic",
      "i2c_en = 1. For prescale = 124 and 4, run a write command and measure SCL",
      "SCL period = 4 x (prescale + 1) clocks (10 us = 100 kHz at 50 MHz for 124)")
    a("", "START / STOP", "", "Basic",
      "CMD = start | write (address 0xA0), then CMD = stop",
      "START: SDA falls while SCL is high; STOP: SDA rises while SCL is high; bus idle (both high) after STOP")
    a("", "Data", "SDA stable while SCL high", "Basic",
      "Protocol monitor on every command of this sheet",
      "SDA changes only while SCL is low, except START and STOP")
    a("Write", "Address", "ACK", "Basic",
      "EEPROM model at 0x50. TXDATA = 0xA0, CMD = start | write",
      "9 SCL pulses; address bits MSB first; ISR.done = 1; STATUS.rx_nack = 0")
    a("", "Address", "NACK", "Error",
      "TXDATA = 0xB2 (no device), CMD = start | write | stop",
      "STATUS.rx_nack = 1; ISR.nack = 1 and ISR.done = 1; STOP generated")
    a("", "Data", "Byte and page write", "Basic",
      "Write 1 byte at 0x0123; write a 32-byte page; read both back",
      "EEPROM model memory and read data match the written bytes")
    a("Read", "Data", "ACK then NACK", "Basic",
      "Random read: start|write 0xA0, addr hi, addr lo, start|write 0xA1 (repeated START), "
      "3 x read (ACK), 1 x read | nack | stop",
      "RXDATA after each read = EEPROM bytes; master drives ACK (SDA low) on bytes 1-3 and releases SDA (NACK) on byte 4")
    a("", "Repeated START", "", "Basic",
      "Part of the random read above",
      "Second START without a STOP before it; EEPROM model accepts it")
    a("", "Sequential read", "Address rollover", "Corner",
      "Read across address 0xFFF -> 0x000",
      "Bytes match the model across the rollover")
    a("Write cycle", "ACK polling", "", "Corner",
      "After a page write, repeat start|write 0xA0 until ACK",
      "First polls get NACK while the model is busy; then ACK; data correct")
    a("Status", "busy", "", "Basic",
      "Poll STATUS.busy during and after a command",
      "busy = 1 while a command runs; 0 when ISR.done is set")
    a("", "bus_busy", "", "Basic",
      "Check STATUS.bus_busy after START, during data, after STOP",
      "bus_busy = 1 from START until STOP")
    a("Control", "Disable", "i2c_en = 0", "Basic",
      "i2c_en = 0: write CMD = start | write; check pins",
      "Command ignored (no ISR.done); scl_oe = sda_oe = 0 (lines released)")
    a("", "CMD", "PSTRB[0] = 0", "Corner",
      "Write CMD = start | write with PSTRB = 4'b1110",
      "No command starts")
    a("", "Pins", "Open drain", "Basic",
      "During all commands check i2c_scl_o and i2c_sda_o",
      "_o is always 0; a line is driven Low only with _oe = 1")
    a("Interrupt", "Gating", "IER x ISR", "Basic",
      "Make done and nack 1; test irq_i2c_o with each IER combination",
      "irq_i2c_o = OR(ISR AND IER)")
    a("", "Clear", "W1C", "Basic",
      "Write ISR = 0; write ISR = 3 with PSTRB = 4'b1110; write 1 to each bit",
      "First two writes change nothing; each later write clears only its own bit")
    return sh


def timer_sheet():
    sh = Sheet("TIMER", "Timer (*) (APB slot 3, base 0x1000_3000)", "Spec sec. Timer; regmap TIMER")
    regs = dict((b, r) for b, _, _, r in regmap.BLOCKS)["timer"]
    register_items(sh, "timer", regs)
    apb_timing_items(sh, "TCMP0", "0x18", "TCMP1", "0x1C")
    a = sh.add
    a("Counter", "No prescaler", "div_en = 0", "Basic",
      "TDR = 0, TCR = timer_en. Read TDR0 N clocks apart (N = 10, 100)",
      "Difference between reads = N (one increment per clock)")
    a("", "Prescaler", "div_val = 0..8", "Basic",
      "For each div_val: TCR = div_val<<8 | div_en | timer_en; measure the clocks between increments",
      "Period = 2^div_val clocks")
    a("", "Prescaler", "Prohibited div_val", "Corner",
      "TCR.div_val = 3, then write div_val = 9, 12, 15 (timer_en = 0)",
      "div_val reads 3 after every write")
    a("", "Enable", "timer_en = 0 holds", "Basic",
      "Count, then clear timer_en; read TDR0 twice 50 clocks apart",
      "Counter does not change while timer_en = 0")
    a("", "64-bit", "Carry into TDR1", "Corner",
      "TDR1 = 0, TDR0 = FFFF_FFF0, timer_en = 1; wait 32 clocks",
      "TDR1 = 1, TDR0 = small value (carry propagated)")
    a("", "64-bit", "Wrap of the full counter", "Corner",
      "TDR1 = TDR0 = FFFF_FFFF minus 4; run 10 clocks",
      "Counter wraps to small values in both words")
    a("", "Write", "Write while counting", "Corner",
      "timer_en = 1, write TDR0 = 1000",
      "Counter continues from 1000")
    a("Compare", "Match", ">= unsigned 64-bit", "Basic",
      "TCMP = 100, count from 0",
      "TISR.cmp_match = 0 while counter < 100, 1 from 100 and stays 1 after")
    a("", "Match", "High word compare", "Corner",
      "TCMP1 = 1, TCMP0 = 0; counter TDR1 = 0, TDR0 = FFFF_FF00",
      "cmp_match = 0 although TDR0 > TCMP0; becomes 1 only after the carry into TDR1")
    a("", "Reset", "No irq after reset", "Basic",
      "After reset set TIER.cmp_ie = 1, timer_en = 1; run 1000 clocks",
      "irq_mtip_o = 0 (TCMP reset to all ones)")
    a("Interrupt", "Gating", "cmp_ie", "Basic",
      "Make cmp_match = 1; toggle TIER.cmp_ie",
      "irq_mtip_o = cmp_ie AND cmp_match")
    a("", "Clear", "Larger compare", "Basic",
      "With irq high, write TCMP to counter + 1000",
      "irq_mtip_o and TISR go 0; rise again when the counter reaches the new value")
    return sh


def irqc_sheet():
    sh = Sheet("IRQC", "Interrupt controller (*) (APB slot 4, base 0x1000_4000)", "Spec sec. Interrupt controller; regmap IRQC")
    regs = dict((b, r) for b, _, _, r in regmap.BLOCKS)["irqc"]
    register_items(sh, "irqc", regs)
    apb_timing_items(sh, "IRQ_ENABLE", "0x04", "IRQ_ENABLE", "0x04")
    a = sh.add
    a("Function", "Pending", "Raw lines", "Basic",
      "Drive each of irq_uart_i, irq_spi_i, irq_i2c_i, irq_gpio_i alone, then all, then none",
      "IRQ_PENDING bits 0..3 = levels of UART, SPI, I2C, GPIO")
    a("", "Status", "All 16 x 16 combinations", "Basic",
      "For every source pattern and every IRQ_ENABLE value",
      "IRQ_STATUS = IRQ_PENDING AND IRQ_ENABLE; irq_meip_o = OR(IRQ_STATUS)")
    a("", "ID", "Priority", "Basic",
      "Same loop as above, read IRQ_ID",
      "IRQ_ID = index of the lowest set bit of IRQ_STATUS + 1 (UART highest); 0 when IRQ_STATUS = 0")
    a("", "No state", "Clear at source", "Basic",
      "Raise a source with its enable set, then drop it",
      "IRQ_PENDING, IRQ_STATUS and irq_meip_o follow the line; nothing stays latched")
    a("", "Masking", "Enable after pending", "Corner",
      "Source high with enable 0, then set the enable",
      "irq_meip_o rises right after the enable write")
    return sh


def gpio_sheet():
    sh = Sheet("GPIO", "GPIO (APB slot 5, base 0x1000_5000)", "Spec sec. GPIO; regmap GPIO")
    regs = dict((b, r) for b, _, _, r in regmap.BLOCKS)["gpio"]
    register_items(sh, "gpio", regs)
    apb_timing_items(sh, "GPIO_OUT", "0x00", "GPIO_OE", "0x04")
    a = sh.add
    a("Output", "Pins", "OUT and OE", "Basic",
      "Walking 1 and walking 0 on GPIO_OUT and on GPIO_OE",
      "gpio_o = GPIO_OUT[7:0], gpio_oe_o = GPIO_OE[7:0] after each write")
    a("Input", "Pins", "Value", "Basic",
      "Drive gpio_i with walking 1, 0x5A, 0xA5; read GPIO_IN",
      "GPIO_IN = gpio_i")
    a("", "Synchroniser", "2-FF delay", "Corner",
      "Change gpio_i and read GPIO_IN in the next clocks",
      "New value is visible 2 clocks after the change, not earlier (spec: all async inputs use a 2-FF synchroniser)")
    a("Interrupt", "Edge", "Rising edge", "Basic",
      "GPIO_IE = 0xFF. For each pin raise gpio_i[n]",
      "GPIO_IS[n] = 1 only for that pin")
    a("", "Edge", "Falling edge and level", "Basic",
      "IE = 0xFF, IS cleared. Lower a high pin; keep a pin high for 100 clocks",
      "No IS bit set by a falling edge or by a steady level")
    a("", "Enable", "IE = 0", "Basic",
      "IE = 0, raise all pins",
      "GPIO_IS stays 0; irq_gpio_o = 0")
    a("", "Output", "irq_gpio_o", "Basic",
      "Set IS bits one by one; then clear IE bits while IS bits are 1",
      "irq_gpio_o = OR(GPIO_IS AND GPIO_IE); clearing IE masks the irq but keeps IS")
    a("", "Clear", "W1C", "Basic",
      "IS = 0xFF. Write 0; write 0xFF with PSTRB = 4'b1110; write 1 to each bit",
      "First two writes change nothing; each later write clears only its own bit")
    return sh


def bus_sheet():
    sh = Sheet("BUS", "AXI4-Lite master adapter, interconnect, SRAM, AXI4-Lite to APB bridge",
               "Spec sec. Memory map, Error responses, AXI4-Lite master, interconnect, SRAM, bridge")
    a = sh.add
    a("Address decode", "SRAM", "In range", "Basic",
      "Write and read 0x0000_0000, 0x0000_2000, 0x0000_3FFC",
      "OKAY response; read data = written data")
    a("", "Unmapped", "Low range", "Error",
      "Read and write 0x0000_4000 and 0x0FFF_FFFC",
      "DECERR (RESP = 2'b11) on R and B; no SRAM or APB access")
    a("", "Unmapped", "High range", "Error",
      "Read and write 0x1001_0000 and 0xFFFF_FFFC",
      "DECERR on R and B")
    a("", "APB slots 0..5", "", "Basic",
      "Read and write offset 0x0 of each window 0x1000_0000 .. 0x1000_5000",
      "Only PSEL[n] of that slot is asserted; PADDR = ADDR[11:0]; OKAY")
    a("", "APB slots 6..15", "", "Error",
      "Read and write 0x1000_6000, 0x1000_A000, 0x1000_FFFC",
      "SLVERR; no PSEL asserted at all")
    a("SRAM", "Byte enables", "WSTRB", "Basic",
      "Write FFFF_FFFF, then 0000_0000 with WSTRB = 0001, 0010, 0100, 1000, 0011, 1100",
      "Only the selected bytes change")
    a("", "Read latency", "", "Basic",
      "Back-to-back reads of different addresses",
      "Each RDATA belongs to its own address; R arrives after the AR handshake")
    a("", "Init file", "$readmemh", "Basic",
      "Load lane files with a known pattern; read the first and last word",
      "Read data = file contents")
    a("APB bridge", "Protocol", "SETUP / ACCESS", "Basic",
      "One write and one read to slot 0",
      "Cycle 1: PSEL = 1, PENABLE = 0; cycle 2: PENABLE = 1; PADDR, PWRITE, PWDATA, PSTRB stable during both",
      "planned SVA: apb_setup_then_access, apb_stable")
    a("", "Protocol", "PSTRB / PPROT", "Basic",
      "Writes with WSTRB = 0001, 1111; a read",
      "PSTRB = WSTRB on writes, 4'b0000 on reads; PPROT = AxPROT")
    a("", "Wait states", "PREADY low", "Corner",
      "Test slave holds PREADY = 0 for 0, 1, 2, 5 cycles",
      "Bridge stays in ACCESS until PREADY = 1; data and response correct")
    a("", "Error", "PSLVERR", "Error",
      "Test slave returns PSLVERR = 1 on a read and on a write",
      "SLVERR on R and B")
    a("", "Ordering", "Write before read", "Corner",
      "Present AW/W and AR in the same cycle",
      "Write APB transfer happens first, then the read")
    a("AXI master", "Handshake", "VALID / READY", "Basic",
      "CPU requests with random slave READY delays",
      "VALID stays High with stable address/data until READY; VALID never waits for READY",
      "planned SVA: axi_valid_stable")
    a("", "Response", "mem_err", "Error",
      "OKAY, SLVERR, DECERR responses for reads and writes",
      "mem_err_i = 0 for OKAY, 1 for SLVERR and DECERR; one mem_ready pulse per request")
    a("", "AxPROT", "Instruction bit", "Basic",
      "Instruction fetch and data load",
      "ARPROT = 3'b101 for fetch, 3'b001 for data")
    a("CPU view", "Faults", "Load / store / fetch", "Error",
      "Program (bus_apb.S) loads, stores and jumps to unmapped and disabled-slot addresses",
      "mcause = 5 / 7 / 1; mtval = faulting address; program continues after the handler")
    return sh


def soc_sheet():
    sh = Sheet("SOC", "SoC integration (CPU + bus + peripherals)", "Spec sec. System overview, RV32IM core")
    a = sh.add
    a("CPU", "ISA", "rv32ui / rv32um / rv32mi", "Basic",
      "make riscv-tests (tb_cpu_wrapper) and TB=cpu_axi",
      "All tests pass except the 4 listed in sw/riscv-tests/expected_fail.txt")
    a("", "Interrupts and faults", "irq_fault.S", "Basic",
      "Local test: MTI, MEI, priority, MIE/MPIE, bus faults",
      "Test reports pass")
    a("Boot", "hello", "", "Basic",
      "make soc PROG=hello",
      "UART line 'Hello from RISC-V SoC!' then '@@PASS'")
    a("Integration", "periph", "Every peripheral", "Basic",
      "make soc PROG=periph: reset values, UART loopback, SPI loopback, GPIO loopback, GPIO edge IRQ via IRQC, "
      "timer IRQ, I2C EEPROM write/read, I2C NACK, bus error trap",
      "9 'ok' lines and '@@PASS'")
    a("", "Interrupt path", "Peripheral -> IRQC -> CPU", "Basic",
      "periph test items 4 and 5",
      "mcause = 0x8000_000B with IRQ_ID = 4; mcause = 0x8000_0007 for the timer")
    a("", "Board demo", "de2_demo in simulation", "Basic",
      "Run de2_demo on tb_soc_top",
      "Banner, 'EEPROM ... PASS' and 'SD ... (no card)' printed")
    return sh


# ---------------------------------------------------------------- workbook
HEAD = ["ID", "Item", "Sub item 1", "Sub item 2", "Method", "Class", "Test sequence",
        "Formal assertion", "Pass condition", "Plan Start", "Plan End", "Actual Start", "Actual End", "PIC"]
WIDTHS = [10, 16, 20, 26, 10, 8, 56, 20, 44, 12, 12, 12, 12, 8]
GREEN = PatternFill("solid", fgColor="FF00B050")
GREY = PatternFill("solid", fgColor="FFF2F2F2")
THIN = Side(style="thin")
THICK = Side(style="thick")
BOX = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
HBOX = Border(left=THICK, right=THICK, top=THICK, bottom=THICK)
FONT = Font(name="Arial", size=10)
BOLD = Font(name="Arial", size=10, bold=True)
WRAP = Alignment(wrap_text=True, vertical="top")


def write_sheet(wb, sh, prefix):
    ws = wb.create_sheet(sh.name)
    ws["B1"] = "%s    (testbench: %s; reference: %s)" % (sh.title, TB[sh.name], sh.spec_ref)
    ws["B1"].font = BOLD
    for i, h in enumerate(HEAD):
        c = ws.cell(row=2, column=2 + i, value=h)
        c.font, c.fill, c.border = BOLD, GREEN, HBOX
        c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        ws.column_dimensions[c.column_letter].width = WIDTHS[i]
    ws.column_dimensions["A"].width = 3
    start, end = PLAN[sh.name]
    for n, r in enumerate(sh.rows):
        item, sub1, sub2, method, cls, seq, formal, passc = r
        vals = ["%s-%02d" % (prefix, n + 1), item, sub1, sub2, method, cls, seq, formal, passc,
                start, end, "", "", PIC]
        for i, v in enumerate(vals):
            c = ws.cell(row=3 + n, column=2 + i, value=v)
            c.font, c.border, c.alignment = FONT, BOX, WRAP
            if item and i == 1:
                c.font = BOLD
    ws.freeze_panes = "C3"
    return len(sh.rows)


def write_svh(sh):
    """tb/unit_tests/vplan/vp_<block>.svh: item count, item list, register-item task."""
    d = os.path.join(HERE, "..", "..", "tb", "unit_tests", "vplan")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "vp_%s.svh" % sh.name.lower())
    L = ["// Generated by doc/vplan/gen_vplan.py. Do not edit.",
         "// Included inside module tb_*; needs tb/common/apb_common.svh first.",
         "localparam string VP_BLOCK = \"%s\";" % sh.name,
         "localparam int    VP_N     = %d;" % len(sh.rows), "", "// Items of this sheet:"]
    grp = sub = ""
    for k, r in enumerate(sh.rows):
        grp = r[0] or grp
        sub = r[1] if (r[0] or r[1]) else sub
        L.append("//   %s-%02d  %s / %s / %s" % (sh.name, k + 1, grp, sub, r[2]))
    if sh.sv:
        L += ["", "// Register items (reset, R/W, RO, WO, reserved) and APB timing items",
              "task automatic vp_regs();"]
        for a12 in sh.snap:
            L.append("  snap_offs.push_back(%s);" % a12)
        L += ["  " + x if x else "" for x in sh.sv]
        L.append("endtask")
    open(path, "w").write("\n".join(L) + "\n")


def main():
    sheets = [uart_sheet(), spi_sheet(), i2c_sheet(), timer_sheet(), irqc_sheet(),
              gpio_sheet(), bus_sheet(), soc_sheet()]
    for sh in sheets:
        write_svh(sh)
    wb = Workbook()
    rd = wb.active
    rd.title = "README"
    counts = {}
    for sh in sheets:
        counts[sh.name] = write_sheet(wb, sh, sh.name)
    lines = [
        ("Verification plan: RISC-V SoC with peripheral interfaces", BOLD),
        ("Generated by doc/vplan/gen_vplan.py from doc/spec/regmap.py and the spec text. "
         "Edit the script, not this file.", FONT),
        ("", FONT),
        ("Columns follow the register checklist template (ID .. PIC).", FONT),
        ("Method: Directed = SystemVerilog directed test in tb/unit_tests (simulation).", FONT),
        ("Class: Basic = normal function; Corner = boundary / simultaneous events; Error = error response or bad input.", FONT),
        ("Formal assertion: SVA planned for later (sva/); empty = none planned yet.", FONT),
        ("Pass condition: what the self-checking testbench compares. ", FONT),
        ("Out of scope (rev 0.2): the (*) advanced PSLVERR checks of each register (not implemented in RTL).", FONT),
        ("Each check in a testbench prints its vplan ID; the end of the log lists PASS / FAIL per ID.", FONT),
        ("", FONT),
        ("Sheet", BOLD),
    ]
    for i, (t, f) in enumerate(lines):
        rd.cell(row=1 + i, column=1, value=t).font = f
    r0 = len(lines) + 1
    for i, sh in enumerate(sheets):
        rd.cell(row=r0 + i, column=1, value=sh.name).font = FONT
        rd.cell(row=r0 + i, column=2, value="%d items" % counts[sh.name]).font = FONT
        rd.cell(row=r0 + i, column=3, value=sh.title).font = FONT
    rd.cell(row=r0 + len(sheets), column=1, value="Total").font = BOLD
    rd.cell(row=r0 + len(sheets), column=2, value="%d items" % sum(counts.values())).font = BOLD
    rd.column_dimensions["A"].width = 12
    rd.column_dimensions["B"].width = 12
    rd.column_dimensions["C"].width = 80
    out = os.path.join(HERE, "soc_vplan.xlsx")
    wb.save(out)
    print("%s: %s, total %d items" % (out, ", ".join("%s %d" % kv for kv in counts.items()),
                                       sum(counts.values())))


if __name__ == "__main__":
    main()
