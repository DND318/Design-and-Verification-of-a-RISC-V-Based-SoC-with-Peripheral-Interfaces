// I2C stimulus
class i2c_stimulus;
  mailbox #(i2c_packet) s2d_mb;
  mailbox #(i2c_packet) d2s_mb;
  i2c_packet            pkt_q[$];

  function new(mailbox #(i2c_packet) s2d_mb, mailbox #(i2c_packet) d2s_mb);
    this.s2d_mb = s2d_mb;
    this.d2s_mb = d2s_mb;
  endfunction

  task send_pkt(i2c_packet pkt);
    pkt_q.push_back(pkt);
  endtask

  task send(i2c_packet pkt);
    i2c_packet r;
    send_pkt(pkt);
    do d2s_mb.get(r); while (r != pkt);
  endtask

  task run();
    i2c_packet pkt;
    while (1) begin
      wait (pkt_q.size() > 0);
      pkt = pkt_q.pop_front();
      s2d_mb.put(pkt);
      $display("%0t: [i2c_stimulus] Sent packet to driver: %s", $time, pkt.sprint());
    end
  endtask
endclass
