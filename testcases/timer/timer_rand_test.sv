// timer_rand_test: random traffic (TIMER-RND)
class timer_rand_test extends timer_base_test;
  function new();
    super.new();
    name = "timer_rand_test";
  endfunction

  virtual task run_scenario();
    timer_packet p;
    int n = 2000;
    int n_wr = 0, n_rd = 0;
    void'($value$plusargs("N=%d", n));
    $display("%0t: [%s] %0d random packets", $time, name, n);
    item("TIMER-RND");
    for (int i = 0; i < n; i++) begin
      p = new();
      if (p.randomize() == 0) begin
        check(1'b0, "randomize() failed");
        break;
      end
      stim.send(p);
      if (p.write) n_wr++; else n_rd++;
    end
    $display("%0t: [%s] %0d writes, %0d reads sent", $time, name, n_wr, n_rd);
  endtask
endclass
