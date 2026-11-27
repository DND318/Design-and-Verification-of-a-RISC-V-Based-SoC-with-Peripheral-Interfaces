// Waveform dump for "make wave": bound into the testbench top by the Makefile.
// Dumps the whole design to the file given by +WAVEFILE=<path> (FST with Verilator).
module wave_dump;
  string wfile;
  initial begin
    if ($value$plusargs("WAVEFILE=%s", wfile)) begin
      $dumpfile(wfile);
      $dumpvars(0);
      $display("[wave_dump] dumping waveform to %s", wfile);
    end
  end
endmodule
