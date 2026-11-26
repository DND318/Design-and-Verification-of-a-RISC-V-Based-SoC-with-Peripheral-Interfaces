// Timer packet
class timer_packet extends apb_packet;
  constraint c_dir  { write dist {1 := 1, 0 := 1}; }
  constraint c_data {
    if (addr == 12'h000) {
      data[31:12] == 20'd0;
      data[11:8] dist {[0:3] :/ 6, [4:8] :/ 2, [9:15] :/ 2};
      data[1] dist {0 := 1, 1 := 1};
      data[0] dist {0 := 1, 1 := 3};
    } else if (addr == 12'h014 || addr == 12'h01C) {
      data dist {32'd0 := 6, [32'd1:32'd2] :/ 2, [32'd3:32'hFFFF_FFFF] :/ 2};
    } else if (addr == 12'h010 || addr == 12'h018) {
      data dist {[32'd0:32'd400] :/ 5, [32'hFFFF_FF00:32'hFFFF_FFFF] :/ 2, [32'd401:32'hFFFF_FEFF] :/ 3};
    }
  }

  function new();
    // TCR, TIER, TISR, TDR0, TDR1, TCMP0, TCMP1 and three reserved offsets
    addr_list = '{12'h000, 12'h004, 12'h008, 12'h010, 12'h014, 12'h018, 12'h01C,
                  12'h00C, 12'h020, 12'hFFC};
  endfunction

`ifdef VERILATOR
  // Same distributions by hand (Verilator ignores the constraint blocks)
  function void post_randomize();
    int r;
    super.post_randomize();
    write = 1'($urandom_range(1));
    r = $urandom_range(9);
    if (addr == 12'h000) begin
      data = 32'd0;
      data[11:8] = (r < 6) ? 4'($urandom_range(3)) : (r < 8) ? 4'($urandom_range(8, 4))
                                                    : 4'($urandom_range(15, 9));
      data[1] = 1'($urandom_range(1));
      data[0] = ($urandom_range(3) != 0);
    end else if (addr == 12'h014 || addr == 12'h01C) begin
      data = (r < 6) ? 32'd0 : (r < 8) ? 32'($urandom_range(2, 1)) : $urandom;
    end else if (addr == 12'h010 || addr == 12'h018) begin
      data = (r < 5) ? 32'($urandom_range(400)) : (r < 7) ? 32'hFFFF_FF00 | 32'($urandom_range(255))
                                                         : $urandom;
    end
  endfunction
`endif
endclass
