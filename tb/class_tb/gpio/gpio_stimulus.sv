// GPIO stimulus
class gpio_stimulus;
  mailbox #(gpio_packet) s2d_mb;
  mailbox #(gpio_packet) d2s_mb;
  gpio_packet            pkt_q[$];

  function new(mailbox #(gpio_packet) s2d_mb, mailbox #(gpio_packet) d2s_mb);
    this.s2d_mb = s2d_mb;
    this.d2s_mb = d2s_mb;
  endfunction

  task send_pkt(gpio_packet pkt);
    pkt_q.push_back(pkt);
  endtask

  // Drive one value and wait until its hold time is over
  task send(gpio_packet pkt);
    gpio_packet r;
    send_pkt(pkt);
    do d2s_mb.get(r); while (r != pkt);
  endtask

  task run();
    gpio_packet pkt;
    while (1) begin
      wait (pkt_q.size() > 0);
      pkt = pkt_q.pop_front();
      s2d_mb.put(pkt);
      $display("%0t: [gpio_stimulus] Sent packet to driver: gpio_i=%h for %0d clocks", $time, pkt.data, pkt.hold);
    end
  endtask
endclass
