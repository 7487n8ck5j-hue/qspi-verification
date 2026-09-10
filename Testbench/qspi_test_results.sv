//=============================================================================
// Class: qspi_test_results
// Purpose:     Pass/fail bookkeeping for the QSPI regression.
//
// REVISION 2026-09-08:
//   [FIX-A] *** The important one. *** Every entry used to be initialised with
//           passed = 1, and qspi_sb::set_test_id() called mark_as_run()
//           immediately. Net effect: any test that merely announced itself and
//           then did nothing was reported as PASS. An empty test body scored a
//           pass. Results are now fail-safe:
//             - passed initialises to 0
//             - a test only reaches PASS if it explicitly records at least one
//               check AND records no failure (see pass()/fail()/check())
//           A test that runs but never checks anything is reported as
//           NO-CHECKS, not PASS, so hollow tests are visible instead of
//           inflating the pass count.
//   [FIX-B] Expanded to 57 test entries migrating legacy criteria into the 
//           new associative array structure.
//   [FIX-C] Uses an associative array keyed by test id, so a typo in a test id
//           is reported instead of silently updating nothing.
//=============================================================================

class qspi_test_results;

  typedef enum int {
    ST_NOT_RUN    = 0,   // never started
    ST_NO_CHECKS  = 1,   // started but never performed a check
    ST_PASS       = 2,   // ran, >=1 check, zero failures
    ST_FAIL       = 3,   // ran, >=1 failure
    ST_UNSUPPORTED= 4    // feature not present in this DUT
  } test_state_e;

  typedef struct {
    string       test_id;
    string       pass_criteria;
    test_state_e state;
    string       status;
    int          checks;      // number of checks recorded
    int          failures;    // number of failed checks
    bit          supported;   // 0 = feature absent from this DUT
  } test_result_t;

  // Ordered id list (preserves report order) + keyed store
  string        order[$];
  test_result_t results[string];
  string        current_test_id = "";

  function new();
    init_test_list();
  endfunction

  // -------------------------------------------------------------------------
  // Registration helpers
  // -------------------------------------------------------------------------
  local function void add(string id, string criteria, bit supported = 1'b1);
    test_result_t r;
    r.test_id       = id;
    r.pass_criteria = criteria;
    r.state         = supported ? ST_NOT_RUN : ST_UNSUPPORTED;
    r.status        = supported ? "NOT RUN"  : "feature not implemented in DUT";
    r.checks        = 0;
    r.failures      = 0;
    r.supported     = supported;
    results[id]     = r;
    order.push_back(id);
  endfunction

  // -------------------------------------------------------------------------
  // Initialize all 57 test entries
  // -------------------------------------------------------------------------
  function void init_test_list();
    order.delete();
    results.delete();

    // --- TC01-TC41 (Legacy Block 1) ---
    add("QSPI-AHB-SDR-01", "Boot Payload Validation");
    add("QSPI-APB-REG-02", "Hardware Flash Reset Pin Validation");
    add("QSPI-PHY-POL-03", "Hardware Auto-Polling Validation");
    add("QSPI-APB-LVL-04", "Legacy SPI Mode FIFO Thresholds");
    add("QSPI-DAC-XIP-05", "QSPI Boot Instruction Fetch");
    add("QSPI-APB-REG-06", "SPI Fast Read Instruction Verification");
    add("QSPI-DAC-XIP-07", "Mode Bit Generation");
    add("QSPI-DAC-XIP-08", "Continuous XIP Mode Entry");
    add("QSPI-PHY-DDR-09", "DDR Protocol Parameters Synchronization");
    add("QSPI-PHY-RST-10", "PHY Master DLL Lock");
    add("QSPI-PHY-SDR-11", "PHY SDR high-speed transfer");
    add("QSPI-PHY-RST-12", "PHY Reset during active transfer");
    add("QSPI-APB-RST-13", "APB Reset aborts transactions");
    add("QSPI-PHY-REG-14", "PHY Configuration registers check");
    add("QSPI-PHY-SDR-15", "Read Data Capturing via Internal Taps");
    add("QSPI-PHY-RST-16", "PHY Software reset assertion");
    add("QSPI-PHY-SDR-17", "Data Learning Pattern (TDP) Training");
    add("QSPI-APB-SRD-18", "APB Single Read Data phase");
    add("QSPI-AHB-ERR-19", "AHB Error response propagation");
    add("QSPI-APB-CFG-20", "SPI Standard configuration modes");
    add("QSPI-PHY-DUM-21", "PHY Dummy cycles alignment");
    add("QSPI-PHY-DUM-22", "Dummy Clock Cycle Generation");
    add("QSPI-APB-PAR-23", "APB Parameter validation");
    add("QSPI-PHY-POL-24", "PHY Clock Phase configuration");
    add("QSPI-PHY-ERR-25", "PHY Protocol error detection");
    add("QSPI-IND-BWC-26", "Indirect mode block write completion");
    add("QSPI-IND-BRC-27", "Indirect mode block read completion");
    add("QSPI-IND-QUE-28", "INDAC Dual Queuing Mechanism");
    add("QSPI-DMA-HSK-29", "DMA Handshake signals (rx/tx_ack)");
    add("QSPI-DAC-MBW-30", "Maximum Bandwidth Fetch Config");
    add("QSPI-DAC-PPL-31", "DAC Prediction Pipeline Configuration");
    add("QSPI-IND-BND-32", "Indirect mode boundary crossing");
    add("QSPI-DAC-POL-33", "DAC Polling mode execution");
    add("QSPI-APB-PAR-34", "SRAM Partition Allocation");
    add("QSPI-AHB-DEC-35", "AHB address decode validation");
    add("QSPI-PHY-ZWS-36", "PHY Zero Wait State timing");
    add("QSPI-PHY-DDR-37", "DSPI/OSPI DDR Protocol (Hardware Level)");
    add("QSPI-AHB-REG-38", "AHB Address Remap / Decoder");
    add("QSPI-IND-LVL-39", "Indirect mode FIFO watermarks");
    add("QSPI-PHY-HSK-40", "PHY Hardware handshake signals");
    add("QSPI-APB-REG-41", "System Interrupt Generation & Clearing");

    // --- TC42-TC57 (Legacy Block 2) ---
    add("QSPI-SPI-ERA-42", "Sector/Block/Chip Erase Sequence");
    add("QSPI-SPI-PGM-43", "Page Program Sequence (WE+Program+Poll)");
    add("QSPI-SPI-SUS-44", "Erase/Program Suspend and Resume");
    add("QSPI-APB-ID-45",  "JEDEC ID Read (RDID 0x9F)");
    add("QSPI-APB-SFD-46", "SFDP Parameter Table Read (JESD216)");
    add("QSPI-AHB-OTP-47", "OTP/Security Register Lock");
    add("QSPI-AHB-WPR-48", "Software Write Protection (BP bits)");
    add("QSPI-PHY-ERR-49", "Illegal Opcode/Unsupported Command");
    add("QSPI-AHB-ERR-50", "AHB Unaligned Access Handling");
    add("QSPI-PHY-ERR-51", "DLL Lock Failure/Timeout Handling");
    add("QSPI-PHY-CLK-52", "Clock Gating During Idle");
    add("QSPI-PHY-CLK-53", "Dynamic Baud Rate Change");
    add("QSPI-AHB-MCS-54", "Multi-CS Sequential Access (CS[0]-CS[3])");
    add("QSPI-APB-CFG-55", "Chip Select Polarity/Decoder Disable");
    add("QSPI-IND-BND-56", "Indirect Transfer at SRAM Boundary");
    add("QSPI-DAC-BND-57", "4-Byte Address Mode (>128MB Flash)");
  endfunction

  // -------------------------------------------------------------------------
  // Test lifecycle
  // -------------------------------------------------------------------------
  function void set_current_test(string test_id);
    current_test_id = test_id;
    if (!((results.exists(test_id)) != 0)) begin
      $display("[QSPI_RESULTS ERROR] Unknown test id '%s' - auto-registering.", test_id);
      add(test_id, "(auto-registered: id not in test list)");
    end
    if (results[test_id].supported) begin
      results[test_id].state    = ST_NO_CHECKS;   // running, nothing verified yet
      results[test_id].status   = "started, no checks yet";
      results[test_id].checks   = 0;
      results[test_id].failures = 0;
    end
  endfunction

  function void mark_as_run(string test_id);
    if (((results.exists(test_id)) != 0) && results[test_id].supported) begin
      if (results[test_id].state == ST_NOT_RUN) begin
        results[test_id].state  = ST_NO_CHECKS;
        results[test_id].status = "started, no checks yet";
      end
    end
  endfunction

  // -------------------------------------------------------------------------
  // Check recording. A test must call these to earn a PASS.
  // -------------------------------------------------------------------------
  function void record_pass(string msg = "");
    if (current_test_id == "" || !((results.exists(current_test_id)) != 0)) return;
    results[current_test_id].checks++;
    if (results[current_test_id].failures == 0) begin
      results[current_test_id].state  = ST_PASS;
      results[current_test_id].status = (msg == "") ? "ok" : msg;
    end
  endfunction

  function void record_fail(string msg = "");
    if (current_test_id == "" || !((results.exists(current_test_id)) != 0)) return;
    results[current_test_id].checks++;
    results[current_test_id].failures++;
    results[current_test_id].state  = ST_FAIL;
    results[current_test_id].status = msg;
  endfunction

  // Single-call checker: returns the condition so tests can branch on it.
  function bit check(bit condition, string msg = "");
    if (condition) record_pass(msg);
    else           record_fail(msg);
    return condition;
  endfunction

  // Backwards-compatible entry point used by the driver/scoreboard.
  function void set_test_pass(bit passed, string status = "");
    if (passed) record_pass(status);
    else        record_fail(status);
  endfunction

  // -------------------------------------------------------------------------
  // Reporting
  // -------------------------------------------------------------------------
  function string state_str(test_state_e s);
    case (s)
      ST_NOT_RUN:     return "NOT RUN";
      ST_NO_CHECKS:   return "NO-CHECKS";
      ST_PASS:        return "PASS";
      ST_FAIL:        return "FAIL";
      ST_UNSUPPORTED: return "N/A (no HW)";
      default:        return "?";
    endcase
  endfunction

  function string get_summary();
    int n_pass = 0, n_fail = 0, n_notrun = 0, n_nochk = 0, n_unsup = 0;
    string summary;

    summary = "\n";
    summary = {summary, "==========================================================================================\n"};
    summary = {summary, "                                TEST RESULTS SUMMARY                                      \n"};
    summary = {summary, "==========================================================================================\n"};
    summary = {summary, "| Test ID             | Pass Criteria                                    | Status      | Chk |\n"};
    summary = {summary, "|---------------------|--------------------------------------------------|-------------|-----|\n"};

    foreach (order[i]) begin
      test_result_t r = results[order[i]];
      case (r.state)
        ST_PASS:        n_pass++;
        ST_FAIL:        n_fail++;
        ST_NOT_RUN:     n_notrun++;
        ST_NO_CHECKS:   n_nochk++;
        ST_UNSUPPORTED: n_unsup++;
        default:        ;
      endcase
      summary = {summary, $sformatf("| %-20s| %-48s | %-11s | %3d |\n",
                                    r.test_id, r.pass_criteria,
                                    state_str(r.state), r.checks)};
    end

    summary = {summary, "==========================================================================================\n"};
    summary = {summary, $sformatf("Total: %0d | PASS: %0d | FAIL: %0d | NO-CHECKS: %0d | NOT RUN: %0d | N/A: %0d\n",
                                  order.size(), n_pass, n_fail, n_nochk, n_notrun, n_unsup)};
    if (n_nochk > 0)
      summary = {summary, "NOTE: NO-CHECKS tests executed but verified nothing - they are NOT passes.\n"};
    if (n_unsup > 0)
      summary = {summary, "NOTE: N/A entries target features this DUT does not implement.\n"};
    summary = {summary, $sformatf("REGRESSION RESULT: %s\n",
                                  (n_fail == 0 && n_pass > 0 &&
                                   n_nochk == 0 && n_notrun == 0) ? "PASS" : "FAIL")};
    summary = {summary, "==========================================================================================\n"};
    return summary;
  endfunction

  function void print_summary();
    $display("%s", get_summary());
  endfunction

  function int get_pass_count();
    int c = 0;
    foreach (order[i]) if (results[order[i]].state == ST_PASS) c++;
    return c;
  endfunction

  function int get_fail_count();
    int c = 0;
    foreach (order[i]) if (results[order[i]].state == ST_FAIL) c++;
    return c;
  endfunction

  function int get_nocheck_count();
    int c = 0;
    foreach (order[i]) if (results[order[i]].state == ST_NO_CHECKS) c++;
    return c;
  endfunction

  function bit get_current_pass();
    if (current_test_id == "" || !((results.exists(current_test_id)) != 0)) return 0;
    return (results[current_test_id].state == ST_PASS);
  endfunction

  function bit regression_passed();
    return (get_fail_count() == 0)
        && (get_pass_count() > 0)
        && (get_nocheck_count() == 0)
        && (get_notrun_count() == 0);
  endfunction

  function int get_notrun_count();
    int c = 0;
    foreach (order[i]) if (results[order[i]].state == ST_NOT_RUN) c++;
    return c;
  endfunction

endclass
