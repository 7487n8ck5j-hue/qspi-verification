//=============================================================================
// Class: qspi_agent
// Purpose:     Container that owns the driver, monitor and scoreboard and wires
//              them to the interface.
//
// REVISION 2026-09-08:
//   [FIX-A] *** Removed the double-accounting. *** send_write()/send_read()
//           used to call sb.process_write()/sb.process_read() directly, while
//           the monitor also called them for the very same bus transfer. Every
//           transaction was scored twice, inflating counts and duplicate-write
//           statistics. The monitor is now the only path into the scoreboard.
//   [FIX-B] set_test_id() no longer implies that the test has passed. It only
//           selects the active test and re-arms the register model; the pass
//           verdict comes from explicit checks (see qspi_test_results).
//   [FIX-C] run() waits for reset de-assertion before starting the monitor, so
//           the monitor does not sample the bus while presetn is low.
//   [FIX-D] Modport-typed virtual interfaces so driver and monitor can only
//           access what their modport allows.
//=============================================================================
class qspi_agent;

  virtual qspi_if      vif;
  qspi_sb              sb;
  qspi_driver          drv;
  qspi_monitor         mon;

  string agent_name;
  bit    started = 1'b0;

  // NOTE: no default on vif_handle - see qspi_driver.sv for the reason.
  function new(string name = "qspi_agent", virtual qspi_if vif_handle);
    agent_name = name;
    vif        = vif_handle;

    sb  = new("qspi_sb");
    drv = new("qspi_driver",  vif_handle, sb);
    mon = new("qspi_monitor", vif_handle, sb);
  endfunction

  // Connect or update the virtual interface across all sub-components
  function void set_interface(virtual qspi_if vif_handle);
    vif = vif_handle;
    if (drv != null) drv.set_interface(vif_handle);
    if (mon != null) mon.set_interface(vif_handle);
  endfunction

  // [FIX-B] select the active test; does NOT record any result
  function void set_test_id(string test_id);
    if (sb != null) sb.set_test_id(test_id);
  endfunction

  // Convenience pass-throughs for test sequences utilizing proper getter
  function void record_pass(string msg = "");
    if (sb != null && sb.get_test_results() != null) sb.get_test_results().record_pass(msg);
  endfunction

  function void record_fail(string msg = "");
    if (sb != null && sb.get_test_results() != null) sb.get_test_results().record_fail(msg);
  endfunction

  // Single-call checker used by test sequences utilizing proper getter
  function bit check(bit condition, string msg = "");
    if (sb != null && sb.get_test_results() != null) return sb.get_test_results().check(condition, msg);
    return condition;
  endfunction

  //-----------------------------------------------------------------
  // Start the monitor thread
  //-----------------------------------------------------------------
  task run();
    if (vif == null) begin
      $display("[%s ERROR] Virtual interface is not assigned to agent!", agent_name);
      return;
    end

    $display("[%s INFO] Starting QSPI Agent monitor thread...", agent_name);
    started = 1'b1;

    fork
      begin
        // [FIX-C] do not sample while reset is asserted
        wait (vif.presetn === 1'b1);
        mon.run();
      end
    join_none
  endtask

  //-----------------------------------------------------------------
  // Transaction API.
  // [FIX-A] These drive the bus only. The monitor observes the resulting
  // transfer and is the single feed into the scoreboard.
  //-----------------------------------------------------------------
  task send_write(qspi_transaction trans);
    if (drv == null) return;
    trans.pwrite = 1'b1;
    drv.drive_write(trans);
  endtask

  task send_read(qspi_transaction trans);
    if (drv == null) return;
    trans.pwrite = 1'b0;
    drv.drive_read(trans);
  endtask

  task write_reg(bit [31:0] addr, bit [31:0] data);
    if (drv != null) drv.drive_write_word(addr, data);
  endtask

  task write_reg_strb(bit [31:0] addr, bit [31:0] data, bit [3:0] strb);
    if (drv != null) drv.drive_write_strb(addr, data, strb);
  endtask

  task read_reg(bit [31:0] addr, output bit [31:0] data);
    if (drv != null) drv.drive_read_addr(addr, data);
    else data = 32'h0;
  endtask

  task read_reg_full(bit [31:0] addr, output bit [31:0] data, output bit slverr);
    if (drv != null) drv.drive_read_full(addr, data, slverr);
    else begin data = 32'h0; slverr = 1'b0; end
  endtask

  //-----------------------------------------------------------------
  // Reporting
  //-----------------------------------------------------------------
  function void report();
    $display("=================================================================");
    $display("[%s REPORT] QSPI Agent Summary", agent_name);
    if (drv != null) drv.print_report();
    if (mon != null) mon.print_report();
    if (sb  != null) sb.print_report();
    $display("=================================================================");
  endfunction

  function qspi_sb get_scoreboard();
    return sb;
  endfunction

  function qspi_test_results get_test_results();
    if (sb != null) return sb.get_test_results();
    return null;
  endfunction

endclass
