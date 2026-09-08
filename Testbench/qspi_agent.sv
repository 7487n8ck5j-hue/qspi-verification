//=============================================================================
// Class: qspi_agent
// Purpose:     SystemVerilog QSPI agent container. Instantiates
//              and manages the qspi_driver, qspi_monitor, and qspi_sb.
//
// CORRECTED: 2026-09-07
//   - Removed broken qspi_sequencer include (was self-referencing)
//   - Fixed send_write to also call mark_as_run
//   - Fixed send_read to forward to scoreboard for comparison
//   - Added set_test_id to properly chain to scoreboard + test_results
//=============================================================================
class qspi_agent;

  virtual qspi_if vif;
  qspi_sb         sb;
  qspi_driver     drv;
  qspi_monitor    mon;

  string agent_name;

  function new(string name = "qspi_agent", virtual qspi_if vif_handle = null);
    agent_name = name;
    vif        = vif_handle;

    // Instantiate sub-components
    sb   = new("qspi_sb");
    drv  = new("qspi_driver", vif, sb);
    mon  = new("qspi_monitor", vif, sb);
  endfunction

  // Connect or update the virtual interface across all sub-components
  function void set_interface(virtual qspi_if vif_handle);
    vif = vif_handle;
    if (drv != null)  drv.set_interface(vif);
    if (mon != null) mon.set_interface(vif);
  endfunction

  // Set the active test ID for the results tracker and scoreboard
  function void set_test_id(string test_id);
    if (sb != null) begin
      sb.set_test_id(test_id);
    end
  endfunction

  // Start concurrent threads for driver and monitor execution
  task run();
    if (vif == null) begin
      $display("[%s ERROR] Virtual interface is not assigned to agent!", agent_name);
      return;
    end

    $display("[%s INFO] Starting QSPI Agent execution threads...", agent_name);

    fork
      // Thread 1: Monitor bus transactions continuously
      begin
        mon.run();
      end
    join_none
  endtask

  // Method to push an explicit write transaction via driver
  task send_write(qspi_transaction trans);
    if (drv != null) begin
      trans.pwrite = 1'b1;
      drv.drive_write(trans);
      // Immediately forward to scoreboard write model for checking
      sb.process_write(trans);
    end
  endtask

  // Method to push an explicit read transaction via driver
  task send_read(qspi_transaction trans);
    if (drv != null) begin
      trans.pwrite = 1'b0;
      drv.drive_read(trans);
      // FIXED: forward to scoreboard for comparison
      sb.process_read(trans);
    end
  endtask

  // Print summary report across agent components
  function void report();
    $display("=================================================================");
    $display("[%s REPORT] QSPI Agent Summary", agent_name);
    if (drv != null)  drv.print_report();
    if (mon != null)  mon.print_report();
    if (sb != null)   sb.print_report();
    $display("=================================================================");
  endfunction

  // Helper getters
  function qspi_sb get_scoreboard();
    return sb;
  endfunction

  function qspi_test_results get_test_results();
    if (sb != null) return sb.get_test_results();
    return null;
  endfunction

endclass

