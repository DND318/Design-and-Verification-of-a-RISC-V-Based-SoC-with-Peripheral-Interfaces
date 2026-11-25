// gpio_rand_test: random traffic (GPIO-RND)
class gpio_rand_test extends gpio_base_test;
  function new();
    super.new();
    name = "gpio_rand_test";
  endfunction

  virtual task run_scenario();
    int n = 1500;
    bit done = 1'b0;
    void'($value$plusargs("N=%d", n));
    $display("%0t: [%s] %0d random APB transfers with random pins", $time, name, n);
    item("GPIO-RND");
    fork
      begin
        apb_traffic(n);
        done = 1'b1;
      end
      begin
        gpio_packet p;
        while (!done) begin
          p = new();
          if (p.randomize() == 0) check(1'b0, "randomize() failed");
          gstim.send(p);
        end
      end
    join
  endtask

  task apb_traffic(input int n);
    apb_packet p;
    for (int i = 0; i < n; i++) begin
      p = new();
      p.addr_list = '{GPIO_OUT, GPIO_OE, GPIO_IN, GPIO_IE, GPIO_IS, GPIO_IS, GPIO_IE, 12'h014, 12'hFFC};
      if (p.randomize() == 0) begin
        check(1'b0, "randomize() failed");
        break;
      end
      // W1C writes clear only a few bits, so GPIO_IS is not always 0
      if (p.write && p.addr == GPIO_IS) p.data = p.data & 32'h0000_0011;
      stim.send(p);
    end
  endtask
endclass
