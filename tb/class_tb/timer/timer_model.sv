// Timer reference model
class timer_model;
  bit [3:0]  div_val;
  bit        div_en;
  bit        timer_en;
  bit        cmp_ie;
  int        presc;
  bit [63:0] cnt;
  bit [63:0] cmp;
  bit        irq;

  function new();
    reset();
  endfunction

  function void reset();
    div_val = 4'd1; div_en = 1'b0; timer_en = 1'b0; cmp_ie = 1'b0;
    presc = 0; cnt = 64'd0; cmp = {64{1'b1}}; irq = 1'b0;
  endfunction

  function bit match();
    return cnt >= cmp;
  endfunction

  static function bit [31:0] merge(bit [31:0] o, bit [31:0] n, bit [3:0] s);
    for (int b = 0; b < 4; b++) if (s[b]) o[8*b +: 8] = n[8*b +: 8];
    return o;
  endfunction

  // Read value of an offset in the current state
  function bit [31:0] read(bit [11:0] addr);
    case (addr[11:2])
      10'h000: return {20'd0, div_val, 6'd0, div_en, timer_en};
      10'h001: return {31'd0, cmp_ie};
      10'h002: return {31'd0, match()};
      10'h004: return cnt[31:0];
      10'h005: return cnt[63:32];
      10'h006: return cmp[31:0];
      10'h007: return cmp[63:32];
      default: return 32'd0;
    endcase
  endfunction

  // One clock edge; wr = 1 when a write transfer completes at this edge
  function void step(bit wr, bit [11:0] addr, bit [31:0] data, bit [3:0] strb);
    int  pmax = (1 << div_val) - 1;
    bit  tick = timer_en && (!div_en || presc >= pmax);
    bit  m    = match();
    bit  any  = (strb != 4'b0);
    bit [9:0] w = addr[11:2];
    // counter: a software write wins over the increment
    if (wr && w == 10'h004 && any)      cnt[31:0]  = merge(cnt[31:0],  data, strb);
    else if (wr && w == 10'h005 && any) cnt[63:32] = merge(cnt[63:32], data, strb);
    else if (tick)                      cnt        = cnt + 64'd1;
    presc = (!timer_en || !div_en || tick) ? 0 : presc + 1;
    irq   = cmp_ie & m;
    if (wr && w == 10'h006) cmp[31:0]  = merge(cmp[31:0],  data, strb);
    if (wr && w == 10'h007) cmp[63:32] = merge(cmp[63:32], data, strb);
    if (wr && w == 10'h000 && strb[0]) begin
      div_en   = data[1];
      timer_en = data[0];
    end
    if (wr && w == 10'h000 && strb[1] && data[11:8] <= 4'd8) div_val = data[11:8];
    if (wr && w == 10'h001 && strb[0]) cmp_ie = data[0];
  endfunction
endclass
