// SPI stimulus
class spi_stimulus;
  mailbox #(spi_packet) s2d_mb;
  mailbox #(spi_packet) d2s_mb;
  spi_packet            pkt_q[$];

  function new(mailbox #(spi_packet) s2d_mb, mailbox #(spi_packet) d2s_mb);
    this.s2d_mb = s2d_mb;
    this.d2s_mb = d2s_mb;
  endfunction

  task send_pkt(spi_packet pkt);
    pkt_q.push_back(pkt);
  endtask

  task run();
    spi_packet pkt;
    while (1) begin
      wait (pkt_q.size() > 0);
      pkt = pkt_q.pop_front();
      s2d_mb.put(pkt);
      $display("%0t: [spi_stimulus] Sent packet to driver: %s", $time, pkt.sprint());
    end
  endtask
endclass
