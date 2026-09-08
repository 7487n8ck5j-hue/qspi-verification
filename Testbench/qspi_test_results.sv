//=============================================================================
// Class: qspi_test_results
// Purpose:     SystemVerilog class tracking pass/fail status for all
//              QSPI test cases.
//
// CORRECTED: 2026-09-07
//   - Expanded from 41 to 57 test entries (TC42-TC57 added)
//   - Fixed TC20 ID from "QSPI-SPI-CFG-20" to "QSPI-APB-CFG-20" (corrected)
//   - Fixed TC28 ID from "QSPI-PHY-IRQ-28" to "QSPI-IND-QUE-28" (corrected)
//   - Fixed TC30 ID from "QSPI-PHY-MBW-30" to "QSPI-DAC-MBW-30" (corrected)
//   - Fixed TC37 pass_criteria to match corrected Hardware Level
//   - Added mark_as_run() call in set_current_test() to prevent stale results
//   - Fixed get_summary() total count to use dynamic $size
//=============================================================================
class qspi_test_results;

  typedef struct {
    string test_id;
    string pass_criteria;
    bit    passed;
    string status;
    bit    was_run;
  } test_result_t;

  // FIXED: expanded from 41 to 57 entries
  test_result_t results[57];
  string current_test_id;

  function new();
    init_test_list();
  endfunction

  // Initialize all 57 test entries with "NOT RUN" status
  function void init_test_list();
    // --- TC01-TC41 (existing, with corrections) ---
    results[0]  = '{test_id: "QSPI-AHB-SDR-01", pass_criteria: "01: Boot Payload Validation", passed: 1, status: "NOT RUN", was_run: 0};
    results[1]  = '{test_id: "QSPI-APB-REG-02", pass_criteria: "02: Hardware Flash Reset Pin Validation", passed: 1, status: "NOT RUN", was_run: 0};
    results[2]  = '{test_id: "QSPI-PHY-POL-03", pass_criteria: "03: Hardware Auto-Polling Validation", passed: 1, status: "NOT RUN", was_run: 0};
    results[3]  = '{test_id: "QSPI-APB-LVL-04", pass_criteria: "04: Legacy SPI Mode FIFO Thresholds", passed: 1, status: "NOT RUN", was_run: 0};
    results[4]  = '{test_id: "QSPI-DAC-XIP-05", pass_criteria: "05: QSPI Boot Instruction Fetch", passed: 1, status: "NOT RUN", was_run: 0};
    results[5]  = '{test_id: "QSPI-APB-REG-06", pass_criteria: "06: SPI Fast Read Instruction Verification", passed: 1, status: "NOT RUN", was_run: 0};
    results[6]  = '{test_id: "QSPI-DAC-XIP-07", pass_criteria: "07: Mode Bit Generation", passed: 1, status: "NOT RUN", was_run: 0};
    results[7]  = '{test_id: "QSPI-DAC-XIP-08", pass_criteria: "08: Continuous XIP Mode Entry", passed: 1, status: "NOT RUN", was_run: 0};
    results[8]  = '{test_id: "QSPI-PHY-DDR-09", pass_criteria: "09: DDR Protocol Parameters Synchronization", passed: 1, status: "NOT RUN", was_run: 0};
    results[9]  = '{test_id: "QSPI-PHY-RST-10", pass_criteria: "10: PHY Master DLL Lock", passed: 1, status: "NOT RUN", was_run: 0};
    results[10] = '{test_id: "QSPI-PHY-SDR-11", pass_criteria: "PHY SDR high-speed transfer", passed: 1, status: "NOT RUN", was_run: 0};
    results[11] = '{test_id: "QSPI-PHY-RST-12", pass_criteria: "PHY Reset during active transfer", passed: 1, status: "NOT RUN", was_run: 0};
    results[12] = '{test_id: "QSPI-APB-RST-13", pass_criteria: "APB Reset aborts transactions", passed: 1, status: "NOT RUN", was_run: 0};
    results[13] = '{test_id: "QSPI-PHY-REG-14", pass_criteria: "PHY Configuration registers check", passed: 1, status: "NOT RUN", was_run: 0};
    results[14] = '{test_id: "QSPI-PHY-SDR-15", pass_criteria: "Read Data Capturing via Internal Taps", passed: 1, status: "NOT RUN", was_run: 0};
    results[15] = '{test_id: "QSPI-PHY-RST-16", pass_criteria: "PHY Software reset assertion", passed: 1, status: "NOT RUN", was_run: 0};
    results[16] = '{test_id: "QSPI-PHY-SDR-17", pass_criteria: "Data Learning Pattern (TDP) Training", passed: 1, status: "NOT RUN", was_run: 0};
    results[17] = '{test_id: "QSPI-APB-SRD-18", pass_criteria: "APB Single Read Data phase", passed: 1, status: "NOT RUN", was_run: 0};
    results[18] = '{test_id: "QSPI-AHB-ERR-19", pass_criteria: "AHB Error response propagation", passed: 1, status: "NOT RUN", was_run: 0};
    // FIXED: TC20 corrected from QSPI-SPI-CFG-20 to QSPI-APB-CFG-20
    results[19] = '{test_id: "QSPI-APB-CFG-20", pass_criteria: "SPI Standard configuration modes", passed: 1, status: "NOT RUN", was_run: 0};
    results[20] = '{test_id: "QSPI-PHY-DUM-21", pass_criteria: "PHY Dummy cycles alignment", passed: 1, status: "NOT RUN", was_run: 0};
    results[21] = '{test_id: "QSPI-PHY-DUM-22", pass_criteria: "Dummy Clock Cycle Generation", passed: 1, status: "NOT RUN", was_run: 0};
    results[22] = '{test_id: "QSPI-APB-PAR-23", pass_criteria: "APB Parameter validation", passed: 1, status: "NOT RUN", was_run: 0};
    results[23] = '{test_id: "QSPI-PHY-POL-24", pass_criteria: "PHY Clock Phase configuration", passed: 1, status: "NOT RUN", was_run: 0};
    results[24] = '{test_id: "QSPI-PHY-ERR-25", pass_criteria: "PHY Protocol error detection", passed: 1, status: "NOT RUN", was_run: 0};
    results[25] = '{test_id: "QSPI-IND-BWC-26", pass_criteria: "Indirect mode block write completion", passed: 1, status: "NOT RUN", was_run: 0};
    results[26] = '{test_id: "QSPI-IND-BRC-27", pass_criteria: "Indirect mode block read completion", passed: 1, status: "NOT RUN", was_run: 0};
    // FIXED: TC28 corrected from QSPI-PHY-IRQ-28 to QSPI-IND-QUE-28
    results[27] = '{test_id: "QSPI-IND-QUE-28", pass_criteria: "INDAC Dual Queuing Mechanism", passed: 1, status: "NOT RUN", was_run: 0};
    results[28] = '{test_id: "QSPI-DMA-HSK-29", pass_criteria: "DMA Handshake signals (rx/tx_ack)", passed: 1, status: "NOT RUN", was_run: 0};
    // FIXED: TC30 corrected from QSPI-PHY-MBW-30 to QSPI-DAC-MBW-30
    results[29] = '{test_id: "QSPI-DAC-MBW-30", pass_criteria: "Maximum Bandwidth Fetch Config", passed: 1, status: "NOT RUN", was_run: 0};
    results[30] = '{test_id: "QSPI-DAC-PPL-31", pass_criteria: "DAC Prediction Pipeline Configuration", passed: 1, status: "NOT RUN", was_run: 0};
    results[31] = '{test_id: "QSPI-IND-BND-32", pass_criteria: "Indirect mode boundary crossing", passed: 1, status: "NOT RUN", was_run: 0};
    results[32] = '{test_id: "QSPI-DAC-POL-33", pass_criteria: "DAC Polling mode execution", passed: 1, status: "NOT RUN", was_run: 0};
    results[33] = '{test_id: "QSPI-APB-PAR-34", pass_criteria: "SRAM Partition Allocation", passed: 1, status: "NOT RUN", was_run: 0};
    results[34] = '{test_id: "QSPI-AHB-DEC-35", pass_criteria: "AHB address decode validation", passed: 1, status: "NOT RUN", was_run: 0};
    results[35] = '{test_id: "QSPI-PHY-ZWS-36", pass_criteria: "PHY Zero Wait State timing", passed: 1, status: "NOT RUN", was_run: 0};
    // FIXED: TC37 pass_criteria updated to reflect corrected Hardware Level
    results[36] = '{test_id: "QSPI-PHY-DDR-37", pass_criteria: "DSPI/OSPI DDR Protocol (Hardware Level)", passed: 1, status: "NOT RUN", was_run: 0};
    results[37] = '{test_id: "QSPI-AHB-REG-38", pass_criteria: "AHB Address Remap / Decoder", passed: 1, status: "NOT RUN", was_run: 0};
    results[38] = '{test_id: "QSPI-IND-LVL-39", pass_criteria: "Indirect mode FIFO watermarks", passed: 1, status: "NOT RUN", was_run: 0};
    results[39] = '{test_id: "QSPI-PHY-HSK-40", pass_criteria: "PHY Hardware handshake signals", passed: 1, status: "NOT RUN", was_run: 0};
    results[40] = '{test_id: "QSPI-APB-REG-41", pass_criteria: "System Interrupt Generation & Clearing", passed: 1, status: "NOT RUN", was_run: 0};

    // --- TC42-TC57 (NEW — added 2026-09-03) ---
    results[41] = '{test_id: "QSPI-SPI-ERA-42", pass_criteria: "Sector/Block/Chip Erase Sequence", passed: 1, status: "NOT RUN", was_run: 0};
    results[42] = '{test_id: "QSPI-SPI-PGM-43", pass_criteria: "Page Program Sequence (WE+Program+Poll)", passed: 1, status: "NOT RUN", was_run: 0};
    results[43] = '{test_id: "QSPI-SPI-SUS-44", pass_criteria: "Erase/Program Suspend and Resume", passed: 1, status: "NOT RUN", was_run: 0};
    results[44] = '{test_id: "QSPI-APB-ID-45", pass_criteria: "JEDEC ID Read (RDID 0x9F)", passed: 1, status: "NOT RUN", was_run: 0};
    results[45] = '{test_id: "QSPI-APB-SFD-46", pass_criteria: "SFDP Parameter Table Read (JESD216)", passed: 1, status: "NOT RUN", was_run: 0};
    results[46] = '{test_id: "QSPI-AHB-OTP-47", pass_criteria: "OTP/Security Register Lock", passed: 1, status: "NOT RUN", was_run: 0};
    results[47] = '{test_id: "QSPI-AHB-WPR-48", pass_criteria: "Software Write Protection (BP bits)", passed: 1, status: "NOT RUN", was_run: 0};
    results[48] = '{test_id: "QSPI-PHY-ERR-49", pass_criteria: "Illegal Opcode/Unsupported Command", passed: 1, status: "NOT RUN", was_run: 0};
    results[49] = '{test_id: "QSPI-AHB-ERR-50", pass_criteria: "AHB Unaligned Access Handling", passed: 1, status: "NOT RUN", was_run: 0};
    results[50] = '{test_id: "QSPI-PHY-ERR-51", pass_criteria: "DLL Lock Failure/Timeout Handling", passed: 1, status: "NOT RUN", was_run: 0};
    results[51] = '{test_id: "QSPI-PHY-CLK-52", pass_criteria: "Clock Gating During Idle", passed: 1, status: "NOT RUN", was_run: 0};
    results[52] = '{test_id: "QSPI-PHY-CLK-53", pass_criteria: "Dynamic Baud Rate Change", passed: 1, status: "NOT RUN", was_run: 0};
    results[53] = '{test_id: "QSPI-AHB-MCS-54", pass_criteria: "Multi-CS Sequential Access (CS[0]-CS[3])", passed: 1, status: "NOT RUN", was_run: 0};
    results[54] = '{test_id: "QSPI-APB-CFG-55", pass_criteria: "Chip Select Polarity/Decoder Disable", passed: 1, status: "NOT RUN", was_run: 0};
    results[55] = '{test_id: "QSPI-IND-BND-56", pass_criteria: "Indirect Transfer at SRAM Boundary", passed: 1, status: "NOT RUN", was_run: 0};
    results[56] = '{test_id: "QSPI-DAC-BND-57", pass_criteria: "4-Byte Address Mode (>128MB Flash)", passed: 1, status: "NOT RUN", was_run: 0};
  endfunction

  function void set_current_test(string test_id);
    current_test_id = test_id;
    foreach (results[i]) begin
      if (results[i].test_id == current_test_id) begin
        results[i].passed = 1;
        results[i].status = "";
        results[i].was_run = 0;  // reset for new run
      end
    end
  endfunction

  function void mark_as_run(string test_id);
    foreach (results[i]) begin
      if (results[i].test_id == test_id) begin
        results[i].was_run = 1;
        return;
      end
    end
  endfunction

  // Update result for the current test
  function void set_test_pass(bit passed, string status = "");
    foreach (results[i]) begin
      if (results[i].test_id == current_test_id) begin
        results[i].passed = passed;
        results[i].status = status;
        results[i].was_run = 1;  // FIXED: mark as run when result is set
        return;
      end
    end
  endfunction

  // Build a formatted table of all test results
  function string get_summary();
    int pass_count = 0;
    int fail_count = 0;
    int not_run_count = 0;

    int total = $size(results);
    string summary;

    summary = "\n";
    summary = {summary, "====================================================================================================\n"};
    summary = {summary, "                                    TEST RESULTS SUMMARY                                        \n"};
    summary = {summary, "====================================================================================================\n"};
    summary = {summary, "| Test ID             | Pass Criteria                                  | Status      |\n"};
    summary = {summary, "|---------------------|------------------------------------------------|-------------|\n"};

    foreach (results[i]) begin
      string status_str;
      if (results[i].test_id == "") continue;
      if (!results[i].was_run) begin
        status_str = "NOT RUN"; not_run_count++;
      end else if (results[i].passed) begin
        status_str = "PASS"; pass_count++;
      end else begin
        status_str = "FAIL"; fail_count++;
      end
      summary = {summary, $sformatf("| %-20s| %-46s | %-11s |\n", results[i].test_id, results[i].pass_criteria, status_str)};
    end

    summary = {summary, "====================================================================================================\n"};
    summary = {summary, $sformatf("Total Tests: %0d | PASS: %0d | FAIL: %0d | NOT RUN: %0d\n", total, pass_count, fail_count, not_run_count)};
    summary = {summary, "====================================================================================================\n"};
    return summary;
  endfunction

  function void print_summary();
    $display("%s", get_summary());
  endfunction

  function int get_pass_count();
    int count = 0;
    foreach (results[i]) if (results[i].was_run && results[i].passed) count++;
    return count;
  endfunction

  function int get_fail_count();
    int count = 0;
    foreach (results[i]) if (results[i].was_run && !results[i].passed) count++;
    return count;
  endfunction

  function bit get_current_pass();
    foreach (results[i]) begin
      if (results[i].test_id == current_test_id) begin
        return results[i].passed;
      end
    end
    return 0;
  endfunction

endclass

