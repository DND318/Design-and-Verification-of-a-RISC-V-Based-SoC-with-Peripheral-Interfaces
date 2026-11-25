// i2c_rand_test: random traffic (I2C-RND)
class i2c_rand_test extends i2c_base_test;
  function new();
    super.new();
    name = "i2c_rand_test";
  endfunction

  virtual task run_scenario();
    int n = 40;
    void'($value$plusargs("N=%d", n));
    $display("%0t: [%s] %0d random rounds", $time, name, n);
    item("I2C-RND");
    enable(4);
    for (int r = 0; r < n; r++) round(r);
    $display("%0t: [%s] %0d commands, %0d bytes, %0d START, %0d STOP, %0d EEPROM write cycles", $time, name,
             sb.n_cmd, sb.n_bytes, sb.n_start, sb.n_stop, env.drv.n_write_cycles);
  endtask

  // Random register reads (all compared by the scoreboard)
  task peek();
    bit [11:0] ro[7] = '{CTRL, PRESCALE, TXDATA, RXDATA, STATUS, IER, ISR};
    bit [31:0] d;
    repeat ($urandom_range(2)) read(ro[$urandom_range(6)], d);
    if ($urandom_range(3) == 0) write(ISR, 32'($urandom_range(3)));
  endtask

  // One command, then wait; START / STOP may be split into their own command
  task rcmd(input bit [31:0] c);
    if ((c & C_START) != 0 && (c & (C_WRITE | C_READ)) != 0 && $urandom_range(1) == 1) begin
      write(CMD, C_START);
      wait_done();
      peek();
      c &= ~C_START;
    end
    if ((c & C_STOP) != 0 && (c & (C_WRITE | C_READ)) != 0 && $urandom_range(1) == 1) begin
      write(CMD, c & ~C_STOP);
      wait_done();
      peek();
      c = C_STOP;
    end
    write(CMD, c);
    wait_done();
    peek();
  endtask

  task rwr(input bit [7:0] b, input bit sta, input bit sto, output bit nk);
    bit [31:0] st;
    write(TXDATA, b);
    rcmd(C_WRITE | (sta ? C_START : 0) | (sto ? C_STOP : 0));
    read(STATUS, st);
    nk = st[1];
  endtask

  task rrd(input bit nk, input bit sto, output bit [7:0] b);
    bit [31:0] d;
    rcmd(C_READ | (nk ? C_NACK : 0) | (sto ? C_STOP : 0));
    read(RXDATA, d);
    b = d[7:0];
  endtask

  task rread(input int n, input string what);
    bit [7:0] b;
    for (int i = 0; i < n; i++) begin
      rrd(i == n - 1, i == n - 1, b);
      check(b === exp_mem[exp_ptr], $sformatf("%s: byte %0d at %h = %h, expected %h", what, i, exp_ptr, b, exp_mem[exp_ptr]));
      exp_ptr++;
    end
  endtask

  task round(input int r);
    i2c_packet  p = new();
    bit [11:0]  a = 12'($urandom);
    int         n = $urandom_range(8, 1);
    int         op = $urandom_range(9);
    int         polls;
    bit         nk;
    bit [31:0]  isr;
    write(PRESCALE, $urandom_range(6));
    write(IER, 32'($urandom_range(3)));
    $display("%0t: [%s] round %0d: PRESCALE %0d, op %0d, address %h, %0d bytes", $time, name, r,
             cfg.prescale, op, a, n);
    case (op)
      0, 1, 2: begin                             // page write
        rwr(EE_W, 1'b1, 1'b0, nk);       check(!nk, "write: control NACKed");
        rwr({4'h0, a[11:8]}, 1'b0, 1'b0, nk);
        rwr(a[7:0], 1'b0, 1'b0, nk);     check(!nk, "write: address NACKed");
        for (int i = 0; i < n; i++) begin
          if (p.randomize() == 0) check(1'b0, "randomize() failed");
          rwr(p.rdata, 1'b0, i == n - 1, nk);
          check(!nk, "write: data NACKed");
          exp_mem[{a[11:5], 5'(a[4:0] + i)}] = p.rdata;
        end
        exp_ptr = {a[11:5], 5'(a[4:0] + n)};
        ee_poll(polls);
      end
      3, 4, 5: begin                             // random read
        rwr(EE_W, 1'b1, 1'b0, nk);       check(!nk, "read: control(W) NACKed");
        rwr({4'h0, a[11:8]}, 1'b0, 1'b0, nk);
        rwr(a[7:0], 1'b0, 1'b0, nk);
        rwr(EE_R, 1'b1, 1'b0, nk);       check(!nk, "read: control(R) NACKed");
        exp_ptr = a;
        rread(n, "random read");
      end
      6, 7: begin                                // current-address read
        rwr(EE_R, 1'b1, 1'b0, nk);       check(!nk, "current read: control(R) NACKed");
        rread($urandom_range(4, 1), "current read");
      end
      default: begin                             // missing device
        rwr(BAD_W | 8'($urandom_range(1)), 1'b1, $urandom_range(1), nk);
        check(nk, "missing device: NACK expected");
        read(STATUS, isr);
        if (isr[2]) rcmd(C_STOP);
      end
    endcase
    write(ISR, 32'h3);
  endtask
endclass
