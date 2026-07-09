# ==============================================================================
# QSPI 41-Test Master Regression Makefile
# ==============================================================================

# Toolchain: Synopsys VCS
VCS     = vcs
CFLAGS  = -sverilog -full64 -debug_access+all -timescale=1ns/1ps

# Project Files
DESIGN  = design.sv
TESTS   = $(sort $(wildcard tb_test_*.sv))

# Output Directories & Files
BUILD_DIR   = build
LOG_DIR     = logs
REPORT_FILE = regression_report.txt

.PHONY: all regress summary clean dirs

# Default target
all: dirs regress summary

# 1. Ensure directories exist
dirs:
	@mkdir -p $(BUILD_DIR) $(LOG_DIR)

# 2. Compile and run all tests
regress: dirs
	@echo "Starting Regression Suite..."
	@for test in $(TESTS); do \
		echo "--------------------------------------------------------"; \
		echo "--> Running $$test"; \
		$(VCS) $(CFLAGS) -o $(BUILD_DIR)/simv_$$test $(DESIGN) $$test; \
		./$(BUILD_DIR)/simv_$$test | tee $(LOG_DIR)/$$test.log; \
	done

# 3. Print the Detailed Pass/Fail Summary AND Save to File
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
clean:
	@echo "--> Cleaning up workspace..."
	@rm -rf $(BUILD_DIR) $(LOG_DIR) *.daidir csrc *.vcd *.log *.key vc_hdrs.h $(REPORT_FILE) regression_summary.txt
