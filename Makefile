# All flows live in sim/Makefile; this file forwards each target there.
# Example: make sim TOP=sync_fifo   ==   make -C sim sim TOP=sync_fifo
# Variables (TOP, TEST, SEED, SUITES, ...) are passed through by make.
TARGETS := all lint build sim run tests units soc uvm regress cov riscv-tests vplan spec check-tools clean
.PHONY: $(TARGETS)
.DEFAULT_GOAL := all

$(TARGETS):
	@$(MAKE) --no-print-directory -C sim $@
