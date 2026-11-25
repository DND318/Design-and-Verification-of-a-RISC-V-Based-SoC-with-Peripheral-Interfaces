// UART stimulus
class uart_stimulus;
  mailbox #(uart_packet) s2d_mb;
  mailbox #(uart_packet) d2s_mb;
  uart_packet            pkt_q[$];

  function new(mailbox #(uart_packet) s2d_mb, mailbox #(uart_packet) d2s_mb);
    this.s2d_mb = s2d_mb;
    this.d2s_mb = d2s_mb;
  endfunction

  task send_pkt(uart_packet pkt);
    pkt_q.push_back(pkt);
  endtask

  // Send one frame and wait until it is on the line
  task send(uart_packet pkt);
    uart_packet r;
    send_pkt(pkt);
    do d2s_mb.get(r); while (r != pkt);
  endtask

  task run();
    uart_packet pkt;
    while (1) begin
      wait (pkt_q.size() > 0);
      pkt = pkt_q.pop_front();
      s2d_mb.put(pkt);
      $display("%0t: [uart_stimulus] Sent packet to driver: %s", $time, pkt.sprint());
    end
  endtask
endclass
