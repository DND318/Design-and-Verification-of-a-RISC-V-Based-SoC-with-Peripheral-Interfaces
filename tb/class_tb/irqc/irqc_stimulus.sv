// IRQC stimulus
class irqc_stimulus;
  mailbox #(irqc_packet) s2d_mb;
  mailbox #(irqc_packet) d2s_mb;
  irqc_packet            pkt_q[$];

  function new(mailbox #(irqc_packet) s2d_mb, mailbox #(irqc_packet) d2s_mb);
    this.s2d_mb = s2d_mb;
    this.d2s_mb = d2s_mb;
  endfunction

  task send_pkt(irqc_packet pkt);
    pkt_q.push_back(pkt);
  endtask

  // Drive one value on the lines and wait until its hold time is over
  task send(irqc_packet pkt);
    irqc_packet r;
    send_pkt(pkt);
    do d2s_mb.get(r); while (r != pkt);
  endtask

  task run();
    irqc_packet pkt;
    while (1) begin
      wait (pkt_q.size() > 0);
      pkt = pkt_q.pop_front();
      s2d_mb.put(pkt);
      $display("%0t: [irqc_stimulus] Sent packet to driver: lines=%b for %0d clocks", $time, pkt.data, pkt.hold);
    end
  endtask
endclass
