# ==============================================================================
# QSPI 41-Test Master Regression Makefile
# ==============================================================================

# Define the compiler and its flags.
# -sverilog enables SystemVerilog features.
# -full64 runs in 64-bit mode.
# -debug_access+all enables waveform dumping (VCD/FSDB).
VCS     = vcs
CFLAGS  = -sverilog -full64 -debug_access+all -timescale=1ns/1ps

# Automatically find all testbench files matching "QSPI-*.sv" in the folder,
# and sort them numerically based on the test number at the end of the filename.
DESIGN  = design.sv
TESTS   = $(shell ls QSPI-*.sv 2>/dev/null | awk -F'-' '{print $$NF, $$0}' | sort -n | cut -d' ' -f2-)

# Define where output files will go to keep the root directory clean.
BUILD_DIR   = build
LOG_DIR     = logs
REPORT_FILE = regression_report.txt

.PHONY: all regress summary clean dirs

# The default command when you just type 'make'. 
# It runs in order: creates folders -> runs tests -> prints summary.
all: dirs regress summary

# 1. Ensure directories exist
# Creates the build and log folders safely (-p prevents errors if they already exist).
dirs:
	@mkdir -p $(BUILD_DIR) $(LOG_DIR)

# 2. Compile and run all tests
# Loops through every testbench. 
# FIX APPLIED: Added an 'if' statement. If VCS fails to build the executable, 
# it safely writes a [FAIL] to the log instead of crashing the flow.
regress: dirs
	@echo "Starting Regression Suite..."
	@for test in $(TESTS); do \
		echo "--------------------------------------------------------"; \
		echo "--> Running $$test"; \
		$(VCS) $(CFLAGS) -o $(BUILD_DIR)/simv_$$test $(DESIGN) $$test; \
		if [ -x $(BUILD_DIR)/simv_$$test ]; then \
			./$(BUILD_DIR)/simv_$$test | tee $(LOG_DIR)/$$test.log; \
		else \
			echo "      -> Error: [FAIL] VCS Compilation Error. Check syntax." > $(LOG_DIR)/$$test.log; \
		fi; \
	done

# 3. Print the Detailed Pass/Fail Summary AND Save to File
# Parses every log file looking for the words [PASS] or [FAIL].
# Prints colorful results to the terminal and plain text to regression_report.txt.
summary:
	@echo ""
	@rm -f $(REPORT_FILE)
	@echo "=======================================================================" | tee -a $(REPORT_FILE)
	@echo "                    DETAILED REGRESSION SUMMARY" | tee -a $(REPORT_FILE)
	@echo " Date & Time: $$(date '+%A, %d %B %Y %T %Z')" | tee -a $(REPORT_FILE)
	@echo "=======================================================================" | tee -a $(REPORT_FILE)
	@pass_cnt=0; fail_cnt=0; \
	if [ ! -d $(LOG_DIR) ] || [ -z "$$(ls -A $(LOG_DIR) 2>/dev/null)" ]; then \
		echo "  No logs found. Did the tests run?" | tee -a $(REPORT_FILE); \
	else \
		for test in $(TESTS); do \
			log="$(LOG_DIR)/$$test.log"; \
			if [ -f "$$log" ]; then \
				if grep -q "\[PASS\]" "$$log"; then \
					printf "  %-20s : \033[0;32mPASS\033[0m\n" "$$test"; \
					printf "  %-20s : PASS\n" "$$test" >> $(REPORT_FILE); \
					pass_cnt=$$((pass_cnt+1)); \
				elif grep -q "\[FAIL\]" "$$log"; then \
					printf "  %-20s : \033[0;31mFAIL\033[0m\n" "$$test"; \
					printf "  %-20s : FAIL\n" "$$test" >> $(REPORT_FILE); \
					err_msg=$$(grep "\[FAIL\]" "$$log" | sed 's/^/      -> Error: /'); \
					echo "$$err_msg"; \
					echo "$$err_msg" >> $(REPORT_FILE); \
					fail_cnt=$$((fail_cnt+1)); \
				else \
					printf "  %-20s : \033[0;33mINCOMPLETE / CRASHED\033[0m\n" "$$test"; \
					printf "  %-20s : INCOMPLETE / CRASHED\n" "$$test" >> $(REPORT_FILE); \
					fail_cnt=$$((fail_cnt+1)); \
				fi; \
			else \
				printf "  %-20s : \033[0;31mMISSING LOG\033[0m\n" "$$test"; \
				printf "  %-20s : MISSING LOG\n" "$$test" >> $(REPORT_FILE); \
				fail_cnt=$$((fail_cnt+1)); \
			fi; \
		done; \
	fi; \
	echo "=======================================================================" | tee -a $(REPORT_FILE); \
	echo " TOTAL PASSED: $$pass_cnt" | tee -a $(REPORT_FILE); \
	echo " TOTAL FAILED: $$fail_cnt" | tee -a $(REPORT_FILE); \
	echo "=======================================================================" | tee -a $(REPORT_FILE)
	@echo ""
	@echo "--> Detailed report successfully saved to: $(REPORT_FILE)"

# 4. Cleanup
# Deletes all generated binaries, logs, waveforms, and directories 
# to return the folder to a pristine state.
clean:
	@echo "--> Cleaning up workspace..."
	@rm -rf $(BUILD_DIR) $(LOG_DIR) *.daidir csrc *.vcd *.log *.key vc_hdrs.h $(REPORT_FILE) regression_summary.txt
