// irqc_rand_test: random traffic (IRQC-RND)
class irqc_rand_test extends irqc_base_test;
  function new();
    super.new();
    name = "irqc_rand_test";
  endfunction

  virtual task run_scenario();
    int n = 1500;
    bit done = 1'b0;
    void'($value$plusargs("N=%d", n));
    $display("%0t: [%s] %0d random APB transfers with random lines", $time, name, n);
    item("IRQC-RND");
    fork
      begin
        apb_traffic(n);
        done = 1'b1;
      end
      begin
        irqc_packet p;
        while (!done) begin
          p = new();
          if (p.randomize() == 0) check(1'b0, "randomize() failed");
          istim.send(p);
        end
      end
    join
  endtask

  task apb_traffic(input int n);
    apb_packet p;
    for (int i = 0; i < n; i++) begin
      p = new();
      p.addr_list = '{IRQ_PENDING, IRQ_ENABLE, IRQ_ENABLE, IRQ_STATUS, IRQ_ID, IRQ_ID, 12'h010, 12'hFFC};
      if (p.randomize() == 0) begin
        check(1'b0, "randomize() failed");
        break;
      end
      stim.send(p);
    end
  endtask
endclass
