# =========================================================================
# Variables
# =========================================================================
# [FIX] Added +define+DUMP_FSDB to enable waveform generation in tb_top.sv
VCS_OPTS = -sverilog -full64 -kdb -debug_access+all -timescale=1ns/1ps +define+DUMP_FSDB
CODE_CVR = -cm line+cond+tgl+fsm+branch+assert

# Expanded deletion list to catch Coverage, Logs, and Verdi junk safely
FILE_TO_DEL = csrc simv simv.daidir ucli.key *.log verdiLog \
              verdi_config_file *.fsdb dump.vcd novas* cm.log \
              simv.vdb urgReport vdCov.conf vdCovLog *.fsdb.* \
              simv.cst .fsm* vc_hdrs.h

# Default top-level source files
TOP_SRC  = ./testbench/tb_top.sv ./rtl/design.sv

# To override sources, run: make build SRC="file1.sv file2.sv"
SRC     ?= $(TOP_SRC)

# =========================================================================
# Targets
# =========================================================================
all: build run

# [IMPROVEMENT] Route compilation output to compile.log
build:
	vcs $(SRC) $(VCS_OPTS) $(CODE_CVR) -l compile.log

# [IMPROVEMENT] Force build dependency to avoid running stale binaries
# Route simulation output to sim.log for easy regression debugging
run: build
	./simv $(CODE_CVR) -l sim.log

sim: build
	./simv -verdi &

wave:
	verdi -ssf fsdbdump.fsdb &

# Generate HTML coverage reports
urgcov:
	urg -dir simv.vdb -format both

# Open Verdi Coverage GUI
verdicov:
	verdi -cov -covdir simv.vdb &

clean:
	rm -rf $(FILE_TO_DEL)

# Declare all command targets as PHONY
.PHONY: all build run sim wave urgcov verdicov clean
