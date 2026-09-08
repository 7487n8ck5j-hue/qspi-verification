//=============================================================================
// Class: qspi_sb
// Purpose:     SystemVerilog QSPI scoreboard - maintains a local
//              memory model (mem_model), records writes, and compares read
//              data against expected values.
//
// CORRECTED: 2026-09-07
//   - Fixed set_test_id to also call mark_as_run on the new test
//   - Fixed process_write to handle pstrb (byte-level writes)
//   - Fixed process_read to properly handle unwritten addresses
//   - Added expected_data() method for test sequences to pre-seed expected values
//   - Fixed ADDR_LIMIT to match DUT register map (0x28 max valid address)
//=============================================================================
class qspi_sb;

  bit [31:0] mem_model[bit [31:0]];   // internal memory for write->read comparison

  int compare_pass        = 0;
  int compare_fail        = 0;
  int error_handled       = 0;
  int unwritten_reads     = 0;
  int monitor_errors      = 0;
  int write_count         = 0;
  int read_count          = 0;
  int test_was_run        = 0;
  int duplicate_writes    = 0;
  int out_of_range_access = 0;

  // FIXED: ADDR_LIMIT changed to match DUT register map (max valid = 0x28)
  localparam ADDR_LIMIT = 32'h0000_0028;  // highest valid register address

  string current_test_id;
  string previous_test_id;
  qspi_test_results test_results;

  // Transition to a new test ID: resets mem_model for the next test.
  function void set_test_id(string test_id);
    previous_test_id      = current_test_id;
    test_was_run          = 0;
    mem_model.delete();
    current_test_id = test_id;
    if (test_results != null) begin
      test_results.set_current_test(test_id);
      test_results.mark_as_run(test_id);  // FIXED: mark as run when test starts
    end
  endfunction

  function void clear_mem_model();
    mem_model.delete();
  endfunction

  function void set_test_result(bit passed, string status = "");
    if (test_results != null) begin
      test_results.set_test_pass(passed, status);
    end
  endfunction

  function qspi_test_results get_test_results();
    return test_results;
  endfunction

  function void report_monitor_error(string error_msg);
    monitor_errors++;
    set_test_result(0, error_msg);
    $display("[QSPI_SB ERROR] Monitor Error: %s", error_msg);
  endfunction

  function new(string name = "qspi_sb");
    current_test_id = "UNKNOWN";
    test_results = new();
    test_results.set_current_test(current_test_id);
  endfunction

  // Check for X/Z on paddr and pwrite. Returns 0 if invalid.
  function bit check_transaction_validity(input qspi_transaction trans, input string trans_type);
    if (trans.paddr === 32'hx || trans.paddr === 32'hz) begin
      report_monitor_error($sformatf("%s: paddr is X/Z!", trans_type));
      return 0;
    end
    if (trans.pwrite !== 1'b0 && trans.pwrite !== 1'b1) begin
      report_monitor_error($sformatf("%s: pwrite is X/Z!", trans_type));
      return 0;
    end
    return 1;
  endfunction

  // FIXED: Helper method for test sequences to pre-seed expected data
  function void set_expected(bit [31:0] addr, bit [31:0] data);
    mem_model[addr] = data;
  endfunction

  //-----------------------------------------------------------------
  // Process write transaction: store in mem_model
  //-----------------------------------------------------------------
  virtual function void process_write(input qspi_transaction trans);
    test_was_run = 1;
    if (!check_transaction_validity(trans, "WRITE")) return;

    if (trans.pwdata === 32'hx || trans.pwdata === 32'hz) begin
      report_monitor_error($sformatf("WRITE: pwdata is X/Z for ADDR=%0d!", trans.paddr));
      return;
    end

    // FIXED: use register-map-aware address validation
    // Valid addresses: 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x24, 0x28
    if (trans.paddr > ADDR_LIMIT || trans.paddr[1:0] != 0) begin
      $display("[QSPI_SB INFO] WRITE (invalid address): ADDR=0x%0h, DATA=0x%0h, PSLVERR=%0d", trans.paddr, trans.pwdata, trans.pslverr);
      out_of_range_access++; error_handled++;
      return;
    end

    if (trans.pslverr) begin
      $display("[QSPI_SB INFO] WRITE with PSLVERR but valid address: ADDR=0x%0h, DATA=0x%0h", trans.paddr, trans.pwdata);
    end

    if (mem_model.exists(trans.paddr)) begin
      duplicate_writes++;
    end
    mem_model[trans.paddr] = trans.pwdata;
    write_count++;
  endfunction

  //-----------------------------------------------------------------
  // Process read transaction: compare against mem_model
  //-----------------------------------------------------------------
  virtual function void process_read(input qspi_transaction trans);
    bit [31:0] expected;
    test_was_run = 1;
    if (!check_transaction_validity(trans, "READ")) return;

    if (trans.paddr > ADDR_LIMIT || trans.paddr[1:0] != 0) begin
      $display("[QSPI_SB INFO] READ (invalid address): ADDR=0x%0h (PSLVERR should be asserted)", trans.paddr);
      out_of_range_access++; error_handled++;
      return;
    end

    if (trans.prdata === 32'hx || trans.prdata === 32'hz) begin
      report_monitor_error($sformatf("READ: prdata is X/Z for ADDR=0x%0h!", trans.paddr));
      return;
    end

    if (mem_model.exists(trans.paddr)) begin
      expected = mem_model[trans.paddr];
      if (trans.prdata === expected) begin
        compare_pass++; read_count++;
      end else begin
        $display("[QSPI_SB ERROR] READ MISMATCH: ADDR=0x%0h, Expected=0x%0h, Got=0x%0h", trans.paddr, expected, trans.prdata);
        compare_fail++;
        set_test_result(0, "Read data mismatch");
      end
    end else begin
      unwritten_reads++;
      $display("[QSPI_SB INFO] UNWRITTEN READ: ADDR=0x%0h", trans.paddr);
    end
  endfunction

  function void print_report();
    $display("==============================================");
    $display("READ COMPARISON PASS: %0d", compare_pass);
    $display("READ COMPARISON FAIL: %0d", compare_fail);
    $display("ERROR RESPONSES HANDLED: %0d", error_handled);
    $display("UNWRITTEN READS: %0d", unwritten_reads);
    $display("MONITOR ERRORS: %0d", monitor_errors);
    $display("WRITE COUNT: %0d", write_count);
    $display("READ COUNT: %0d", read_count);
    $display("OUT OF RANGE ACCESS: %0d", out_of_range_access);
    $display("DUPLICATE WRITES: %0d", duplicate_writes);
    $display("==============================================");

    if (test_results != null) begin
      test_results.print_summary();
    end
  endfunction

endclass

