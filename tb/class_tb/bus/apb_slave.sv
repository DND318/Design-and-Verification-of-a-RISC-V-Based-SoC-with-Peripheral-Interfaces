// APB slave model (16 slots, wait states, PSLVERR)
class apb_slave;
  virtual apbm_if dut_vif;
  bit [31:0]      mem[16][1024];
  int unsigned    wait_n[16];
  bit             err_rd[16], err_wr[16];
  int unsigned    acnt;

  function new(virtual apbm_if dut_vif);
    this.dut_vif = dut_vif;
  endfunction

  static function int slot_of(bit [15:0] s);
    for (int i = 0; i < 16; i++) if (s[i]) return i;
    return -1;
  endfunction

  task run();
    int        s;
    bit [31:0] w;
    dut_vif.prdata  = '0;
    dut_vif.pready  = '0;
    dut_vif.pslverr = '0;
    while (1) begin
      @(posedge dut_vif.clk);
      #1;
      dut_vif.pready  = '0;
      dut_vif.pslverr = '0;
      if (dut_vif.rst_n !== 1'b1 || dut_vif.psel == 16'd0) continue;
      s = slot_of(dut_vif.psel);
      if (dut_vif.penable !== 1'b1) begin          // SETUP
        acnt = 0;
        dut_vif.prdata[32*s +: 32] = mem[s][dut_vif.paddr[11:2]];
      end else begin                              // ACCESS
        if (acnt >= wait_n[s]) begin
          dut_vif.pready[s]  = 1'b1;
          dut_vif.pslverr[s] = dut_vif.pwrite ? err_wr[s] : err_rd[s];
          if (dut_vif.pwrite && !err_wr[s]) begin
            w = mem[s][dut_vif.paddr[11:2]];
            for (int b = 0; b < 4; b++)
              if (dut_vif.pstrb[b]) w[8*b +: 8] = dut_vif.pwdata[8*b +: 8];
            mem[s][dut_vif.paddr[11:2]] = w;
          end
        end
        acnt++;
      end
    end
  endtask
endclass
