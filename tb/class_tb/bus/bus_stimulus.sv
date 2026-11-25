// Bus stimulus
class bus_stimulus;
  mailbox #(bus_packet) s2d_mb;
  mailbox #(bus_packet) d2s_mb;
  bus_packet            pkt_q[$];

  function new(mailbox #(bus_packet) s2d_mb, mailbox #(bus_packet) d2s_mb);
    this.s2d_mb = s2d_mb;
    this.d2s_mb = d2s_mb;
  endfunction

  task send_pkt(bus_packet pkt);
    pkt_q.push_back(pkt);
  endtask

  task send(bus_packet pkt);
    bus_packet r;
    send_pkt(pkt);
    do d2s_mb.get(r); while (r != pkt);
  endtask

  task run();
    bus_packet pkt;
    while (1) begin
      wait (pkt_q.size() > 0);
      pkt = pkt_q.pop_front();
      s2d_mb.put(pkt);
      if ($test$plusargs("VERBOSE")) $display("%0t: [bus_stimulus] Sent packet to driver: %s", $time, pkt.sprint());
    end
  endtask
endclass
