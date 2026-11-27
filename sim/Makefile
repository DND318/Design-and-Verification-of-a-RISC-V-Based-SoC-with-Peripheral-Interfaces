# Simulation flow. Run from sim/ or from the repo root (the root Makefile forwards here).
#   make lint                                            Verilator lint of all RTL (.v parsed as Verilog-2005)
#   make sim  [TOP=sync_fifo] [SIM=verilator|xsim] [SEED=n] [PLUSARGS="+A=1"]   directed test (tb/unit_tests)
#   make build TOP=timer [SIM=verilator|xsim]            class-based testbench (tb/class_tb/<TOP>): compile once
#   make run   TOP=timer TESTNAME=timer_cmp_test [SEED=n] [PLUSARGS=+VERBOSE]   run one test, no recompile
#   make tests TOP=timer [SEED=n]                        build, then run every test of testcases/<TOP>/
#   make wave  TOP=uart TESTNAME=uart_rx_test [TAG=buggy] [SIM=verilator|xsim] [SEED=n]
#                                                        run one test with a waveform dump:
#                                                        sim/wave/<TOP>_<TESTNAME>[_<TAG>].fst (Verilator, open with gtkwave)
#                                                        or .wdb (XSim, open with xsim -gui / Vivado)
#   make units [SIM=verilator|xsim]                      every block-level directed test in UNIT_TOPS
#   make soc  [PROG=hello] [SIM=verilator|xsim]          build sw/tests/<PROG>.c and run it on tb_soc_top
#   make uvm  [TOP=sync_fifo] TEST=fifo_smoke_test [SEED=n] [COV=1]   UVM on XSim
#   make regress [TOP=sync_fifo] [SEEDS=5] [COV=1]       all UVM tests x seeds
#   make cov                                             coverage report (xcrg, HTML)
#   make riscv-tests [SUITES="rv32ui rv32um rv32mi local"] [WAIT=3] [SEED=n] [TB=cpu_wrapper|cpu_axi]
#                                                        riscv-tests on tb_cpu_wrapper or tb_cpu_axi (Verilator)
#   make vplan [BLOCKS="UART SPI ..."] [VPFLAGS=--skip-programs]
#                                                        every directed test, one PASS/FAIL line per vplan ID
#                                                        (sim/report/vplan_results.csv)
#   make spec | check-tools | clean
# Filelists (*.f) hold paths relative to the repo root; they are made absolute in work/.

SHELL      := /bin/bash
PROJ_ROOT  := $(abspath ..)
SIM        ?= verilator
TOP        ?= sync_fifo
TEST       ?= fifo_smoke_test
SEED       ?= 1
SEEDS      ?= 5
COV        ?= 0
SUITES     ?= rv32ui rv32um rv32mi local
WAIT       ?= 3
UVM_TESTS  ?= fifo_smoke_test fifo_rand_test fifo_full_empty_test
LINT_TOPS  ?= sync_fifo cpu_wrapper soc_top
UNIT_TOPS  ?= sync_fifo uart_apb spi_apb i2c_apb timer_apb irqc_apb gpio_apb bus_sys
PLUSARGS   ?=
TESTNAME   ?= $(TOP)_base_test
# top module: "testbench" for a class-based testbench in the course style
# (tb/class_tb/<TOP>/testbench.sv), otherwise tb_<TOP>
TB_TOP     ?= $(if $(wildcard $(PROJ_ROOT)/tb/class_tb/$(TOP)/testbench.sv),testbench,tb_$(TOP))
# tests of a class-based testbench: every "class <name> extends <TOP>_base_test" in testcases/<TOP>/
TESTS      ?= $(shell sed -n 's/^class \([A-Za-z0-9_]*\) extends $(TOP)_base_test.*/\1/p' $(PROJ_ROOT)/testcases/$(TOP)/*.sv 2>/dev/null)
TAG        ?=
WAVE_DIR   := $(PROJ_ROOT)/sim/wave
WAVE_NAME  := $(TOP)_$(TESTNAME)$(if $(TAG),_$(TAG))
PROG       ?= hello
TB         ?= cpu_wrapper

WORK       := $(PROJ_ROOT)/sim/work
REPORT     := $(PROJ_ROOT)/sim/report
CHECK_LOG  := bash $(PROJ_ROOT)/scripts/check_log.sh

VERILATOR_FLAGS := -Wall -Wno-DECLFILENAME --timing --assert
VERILATOR_TB    := -Wno-fatal -Wno-VARHIDDEN -Wno-SYNCASYNCNET -Wno-BLKSEQ -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL
XVLOG_FLAGS     := -sv --nolog
XELAB_FLAGS     := -timescale 1ns/1ps -debug typical --nolog
COVDB           := $(WORK)/xsim_cov

ifeq ($(COV),1)
XELAB_COV := -cc_type sbct -cc_db $(TEST)_$(SEED) -cc_dir $(COVDB)
XSIM_COV  := -cov_db_dir $(COVDB) -cov_db_name $(TEST)_$(SEED)
endif
XSIM_PLUSARGS := $(patsubst +%,-testplusarg %,$(PLUSARGS))

# $(call absf,<list.f>) -> work/<list>.abs.f with absolute paths
absf = mkdir -p $(WORK) && sed -E 's\#^(-i[[:space:]]+)?([^-/[:space:]][^[:space:]]*)\#\1$(PROJ_ROOT)/\2\#' \
       $(PROJ_ROOT)/sim/$(1) > $(WORK)/$(basename $(1)).abs.f

.PHONY: all lint build sim run tests wave units soc uvm regress cov riscv-tests vplan spec check-tools clean

all: lint sim

check-tools:
	@bash $(PROJ_ROOT)/scripts/check_tools.sh

lint:
	@$(call absf,rtl.f)
	@for t in $(LINT_TOPS); do \
	  echo "== lint $$t"; \
	  verilator --lint-only $(VERILATOR_FLAGS) +1364-2005ext+v -f $(WORK)/rtl.abs.f --top-module $$t || exit 1; \
	done
	@echo "LINT CLEAN"

# Compile tb_<TOP> (filelist sim/tb_<TOP>.f) without running it
build:
	@mkdir -p $(REPORT)
	@$(call absf,tb_$(TOP).f)
ifeq ($(SIM),verilator)
	mkdir -p $(WORK)/verilator/$(TOP)
	sed -E 's#^-i[[:space:]]+(.*)#+incdir+\1#' $(WORK)/tb_$(TOP).abs.f > $(WORK)/tb_$(TOP).vl.f
	verilator --binary $(VERILATOR_FLAGS) $(VERILATOR_TB) -f $(WORK)/tb_$(TOP).vl.f \
	  --top-module $(TB_TOP) -Mdir $(WORK)/verilator/$(TOP) -o sim_$(TOP)
else ifeq ($(SIM),xsim)
	cd $(WORK) && \
	xvlog $(XVLOG_FLAGS) -f tb_$(TOP).abs.f && \
	xelab $(XELAB_FLAGS) $(TB_TOP) -s tb_$(TOP)
else
	$(error SIM must be verilator or xsim)
endif

sim: build
ifeq ($(SIM),verilator)
	$(WORK)/verilator/$(TOP)/sim_$(TOP) +verilator+seed+$(SEED) $(PLUSARGS) 2>&1 | tee $(REPORT)/sim_$(TOP).log
else
	cd $(WORK) && xsim tb_$(TOP) -R -sv_seed $(SEED) $(XSIM_PLUSARGS) 2>&1 | tee $(REPORT)/sim_$(TOP).log
endif
	@$(CHECK_LOG) $(REPORT)/sim_$(TOP).log

# One test of a class-based testbench (compile once, run many). The test name
# is passed twice: +<test name> for testbench.sv ($test$plusargs, course style)
# and +TESTNAME=<test name> for the older tb_<TOP>.sv.
run:
	@mkdir -p $(REPORT)
ifeq ($(SIM),verilator)
	$(WORK)/verilator/$(TOP)/sim_$(TOP) +$(TESTNAME) +TESTNAME=$(TESTNAME) +verilator+seed+$(SEED) $(PLUSARGS) 2>&1 | \
	  tee $(REPORT)/sim_$(TOP)_$(TESTNAME).log
else
	cd $(WORK) && xsim tb_$(TOP) -R -sv_seed $(SEED) -testplusarg $(TESTNAME) -testplusarg TESTNAME=$(TESTNAME) $(XSIM_PLUSARGS) 2>&1 | \
	  tee $(REPORT)/sim_$(TOP)_$(TESTNAME).log
endif
	@$(CHECK_LOG) $(REPORT)/sim_$(TOP)_$(TESTNAME).log

tests: build
	@pass=0; fail=0; \
	for t in $(TESTS); do \
	  if $(MAKE) --no-print-directory run TOP=$(TOP) TESTNAME=$$t SIM=$(SIM) SEED=$(SEED) PLUSARGS="$(PLUSARGS)" > /dev/null 2>&1; \
	  then pass=$$((pass+1)); echo "PASS $$t"; \
	  else fail=$$((fail+1)); echo "FAIL $$t (see sim/report/sim_$(TOP)_$$t.log)"; fi; \
	done; \
	echo "tests: $$pass passed, $$fail failed"; [ $$fail -eq 0 ]

# One test with a waveform dump.
# Verilator: separate build (work/verilator/<TOP>_wave) with --trace-fst and tb/common/wave_dump.sv
#   bound into the testbench top, so the normal build used by "make tests" / "make vplan" stays fast.
#   --no-trace-params: Verilator 5.020 crashes when it dumps parameters of the class testbenches.
# XSim: the normal snapshot (xelab -debug typical) logs every signal into a .wdb.
wave:
	@mkdir -p $(REPORT) $(WAVE_DIR)
ifeq ($(SIM),verilator)
	@$(call absf,tb_$(TOP).f)
	@echo "bind $(TB_TOP) wave_dump u_wave_dump();" > $(WORK)/wave_bind_$(TOP).sv
	mkdir -p $(WORK)/verilator/$(TOP)_wave
	sed -E 's#^-i[[:space:]]+(.*)#+incdir+\1#' $(WORK)/tb_$(TOP).abs.f > $(WORK)/tb_$(TOP).vl.f
	verilator --binary $(VERILATOR_FLAGS) $(VERILATOR_TB) --trace-fst --no-trace-params -f $(WORK)/tb_$(TOP).vl.f \
	  $(PROJ_ROOT)/tb/common/wave_dump.sv $(WORK)/wave_bind_$(TOP).sv \
	  --top-module $(TB_TOP) -Mdir $(WORK)/verilator/$(TOP)_wave -o sim_$(TOP)_wave
	$(WORK)/verilator/$(TOP)_wave/sim_$(TOP)_wave +$(TESTNAME) +TESTNAME=$(TESTNAME) +verilator+seed+$(SEED) \
	  +WAVEFILE=$(WAVE_DIR)/$(WAVE_NAME).fst $(PLUSARGS) 2>&1 | tee $(REPORT)/wave_$(WAVE_NAME).log; \
	  exit $${PIPESTATUS[0]}
	-@$(CHECK_LOG) $(REPORT)/wave_$(WAVE_NAME).log
	@echo "Waveform: sim/wave/$(WAVE_NAME).fst"
	@echo "Open:     gtkwave sim/wave/$(WAVE_NAME).fst sim/wave_cfg/$(TOP).gtkw &"
else ifeq ($(SIM),xsim)
	$(MAKE) --no-print-directory build TOP=$(TOP) SIM=xsim
	@printf 'log_wave -recursive *\nrun all\nquit\n' > $(WORK)/wave_all.tcl
	cd $(WORK) && xsim tb_$(TOP) -sv_seed $(SEED) -testplusarg $(TESTNAME) -testplusarg TESTNAME=$(TESTNAME) \
	  $(XSIM_PLUSARGS) -wdb $(WAVE_DIR)/$(WAVE_NAME).wdb -tclbatch wave_all.tcl 2>&1 | tee $(REPORT)/wave_$(WAVE_NAME).log
	-@$(CHECK_LOG) $(REPORT)/wave_$(WAVE_NAME).log
	@echo "Waveform: sim/wave/$(WAVE_NAME).wdb   (open: xsim -gui sim/wave/$(WAVE_NAME).wdb)"
else
	$(error SIM must be verilator or xsim)
endif

units:
	@pass=0; fail=0; \
	for t in $(UNIT_TOPS); do \
	  if $(MAKE) --no-print-directory sim TOP=$$t SIM=$(SIM) SEED=$(SEED) > /dev/null 2>&1; \
	  then pass=$$((pass+1)); echo "PASS $$t"; \
	  else fail=$$((fail+1)); echo "FAIL $$t (see sim/report/sim_$$t.log)"; fi; \
	done; \
	echo "units: $$pass passed, $$fail failed"; [ $$fail -eq 0 ]

soc:
	$(MAKE) --no-print-directory -C $(PROJ_ROOT)/sw PROG=$(PROG)
	$(MAKE) --no-print-directory sim TOP=soc_top SIM=$(SIM) SEED=$(SEED) \
	  PLUSARGS="+PROG=$(PROJ_ROOT)/sw/build/$(PROG) $(PLUSARGS)"

uvm:
	@mkdir -p $(REPORT)
	@$(call absf,uvm_$(TOP).f)
	cd $(WORK) && \
	xvlog $(XVLOG_FLAGS) -L uvm -f uvm_$(TOP).abs.f && \
	xelab $(XELAB_FLAGS) -L uvm tb_top_$(TOP) -s uvm_$(TOP)_$(TEST)_$(SEED) $(XELAB_COV) && \
	xsim uvm_$(TOP)_$(TEST)_$(SEED) -R -sv_seed $(SEED) -testplusarg UVM_TESTNAME=$(TEST) \
	  -testplusarg UVM_VERBOSITY=UVM_LOW $(XSIM_COV) 2>&1 | tee $(REPORT)/uvm_$(TEST)_$(SEED).log
	@$(CHECK_LOG) $(REPORT)/uvm_$(TEST)_$(SEED).log

regress:
	@pass=0; fail=0; \
	for t in $(UVM_TESTS); do for s in $$(seq 1 $(SEEDS)); do \
	  if $(MAKE) --no-print-directory uvm TOP=$(TOP) TEST=$$t SEED=$$s COV=$(COV) > /dev/null 2>&1; \
	  then pass=$$((pass+1)); echo "PASS $$t seed=$$s"; \
	  else fail=$$((fail+1)); echo "FAIL $$t seed=$$s (see sim/report/uvm_$${t}_$$s.log)"; fi; \
	done; done; \
	echo "regress: $$pass passed, $$fail failed"; [ $$fail -eq 0 ]

cov:
	@mkdir -p $(REPORT)
	cd $(WORK) && xcrg -report_format html -dir xsim.covdb -report_dir $(REPORT)/cov_func
	@if [ -d $(COVDB) ]; then cd $(WORK) && \
	  xcrg -cc_report -cc_dir $(COVDB) -report_format html -report_dir $(REPORT)/cov_code; fi
	@echo "Open sim/report/cov_func/dashboard.html"

riscv-tests:
	@mkdir -p $(REPORT)
	TB=$(TB) SEED=$(SEED) WAIT=$(WAIT) bash $(PROJ_ROOT)/scripts/run_riscv_tests.sh $(SUITES) 2>&1 | tee $(REPORT)/riscv_tests.log; \
	  exit $${PIPESTATUS[0]}

vplan:
	cd $(PROJ_ROOT) && python3 scripts/vplan_report.py $(VPFLAGS) $(BLOCKS)

spec:
	cd $(PROJ_ROOT)/doc/spec && python3 gen_spec.py && \
	  pdflatex -interaction=nonstopmode soc_spec.tex >/dev/null && \
	  pdflatex -interaction=nonstopmode soc_spec.tex >/dev/null && echo "doc/spec/soc_spec.pdf rebuilt"

clean:
	rm -rf $(WORK) $(REPORT) $(WAVE_DIR)
