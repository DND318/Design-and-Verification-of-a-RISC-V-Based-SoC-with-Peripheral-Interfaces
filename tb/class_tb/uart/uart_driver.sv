// UART driver: remote transmitter on uart_rx_i
class uart_driver;
  mailbox #(uart_packet) s2d_mb;
  mailbox #(uart_packet) d2s_mb;
  virtual uart_if        dut_vif;

  function new(virtual uart_if dut_vif, mailbox #(uart_packet) s2d_mb, mailbox #(uart_packet) d2s_mb);
    this.dut_vif = dut_vif;
    this.s2d_mb  = s2d_mb;
    this.d2s_mb  = d2s_mb;
  endfunction

  // One level on the line for n clocks
  task put_bit(bit v, int unsigned n);
    dut_vif.rx = v;
    repeat (n) @(posedge dut_vif.clk);
    #3;
  endtask

  task run();
    uart_packet pkt;
    dut_vif.rx = 1'b1;                           // idle line

    while (1) begin
      s2d_mb.get(pkt);
      $display("%0t: [uart_driver] Get packet from stimulus: %s", $time, pkt.sprint());
      @(posedge dut_vif.clk);
      #3;
      case (pkt.kind)
        UART_GLITCH: put_bit(1'b0, pkt.glitch_clks);
        UART_SKEW: begin
          bit [9:0] f = {1'b1, pkt.data, 1'b0};
          for (int i = 0; i < 10; i++)
            put_bit(f[i], (i % 2 == 0) ? pkt.div + 1 + pkt.skew : pkt.div + 1 - pkt.skew);
        end
        default: begin
          put_bit(1'b0, pkt.div + 1);                                    // start
          for (int i = 0; i < 8; i++) put_bit(pkt.data[i], pkt.div + 1); // data, LSB first
          if (pkt.par != 2'b00)
            put_bit(uart_packet::par_bit(pkt.data, pkt.par) ^ pkt.bad_par, pkt.div + 1);
          put_bit(!pkt.bad_stop[0], pkt.div + 1);                        // stop 1
          if (pkt.stop2) put_bit(!pkt.bad_stop[1], pkt.div + 1);         // stop 2
        end
      endcase
      dut_vif.rx = 1'b1;                         // back to idle
      d2s_mb.put(pkt);                           // done
    end
  endtask
endclass
