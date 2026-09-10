//=============================================================================
// Class: qspi_monitor
// Purpose:     Passive APB monitor. Reconstructs every completed APB transfer
//              and forwards it to the scoreboard.
//
// REVISION 2026-09-08:
//   [FIX-A] *** The critical fix. *** The old monitor waited for pready and
//           then did one more @(posedge pclk) before sampling prdata,
//           "to let DUT NBA settle". By that edge the driver had already
//           dropped PSEL/PENABLE, and since the DUT drives prdata
//           combinationally it had collapsed to 0. Every read comparison was
//           therefore performed against 0x00000000. Measured on the real DUT:
//               correct sample point : 0x000000A5
//               old monitor sample   : 0x00000000
//           The monitor now samples through the cb_mon clocking block on the
//           same edge that pready is observed high, which is the defined APB
//           capture point.
//   [FIX-B] The transfer is detected as the single cycle where
//           psel && penable && pready, so each APB transfer is reported
//           exactly once. No open-ended "wait for penable to fall" loop.
//   [FIX-C] Address/control fields are sampled from the same clocking-block
//           edge as the data, so the whole transaction is coherent.
//   [FIX-D] Removed the polling while-loops with magic 10000/100 iteration
//           caps; the monitor is now a simple non-terminating sampler that
//           cannot spuriously give up on a legal idle bus.
//=============================================================================
class qspi_monitor;

  virtual qspi_if vif;
  qspi_sb sb;

  int monitor_reads   = 0;
  int monitor_writes  = 0;
  int monitor_errors  = 0;

  // Optional transaction stream for tests that want to inspect traffic
  qspi_transaction observed[$];
  bit collect_enable = 1'b0;

  // NOTE: no default on vif_handle - see qspi_driver.sv for the reason.
  function new(string name = "qspi_monitor", virtual qspi_if vif_handle,
               qspi_sb sb_handle = null);
    vif = vif_handle;
    sb  = sb_handle;
  endfunction

  function void set_interface(virtual qspi_if vif_handle);
    vif = vif_handle;
  endfunction

  function void set_scoreboard(qspi_sb sb_handle);
    sb = sb_handle;
  endfunction

  //-----------------------------------------------------------------
  // run: sample every completed APB transfer
  //-----------------------------------------------------------------
  task run();
    qspi_transaction trans;

    if (vif == null) begin
      $display("[QSPI_MON ERROR] Virtual interface handle is null!");
      return;
    end

    forever begin
      @(vif.cb_mon);

      // Reset: nothing to observe
      if (vif.presetn !== 1'b1) continue;

      // [FIX-B] a transfer completes on the edge where all three are true.
      // With pready tied high in this DUT that is the ACCESS cycle itself.
      if (vif.cb_mon.psel === 1'b1 &&
          vif.cb_mon.penable === 1'b1 &&
          vif.cb_mon.pready === 1'b1) begin

        trans = new();

        // [FIX-C] every field from the same sampling edge
        trans.presetn = vif.presetn;
        trans.paddr   = vif.cb_mon.paddr;
        trans.pwrite  = vif.cb_mon.pwrite;
        trans.pwdata  = vif.cb_mon.pwdata;
        trans.pstrb   = vif.cb_mon.pstrb;
        trans.pready  = vif.cb_mon.pready;
        // [FIX-A] prdata sampled here, not one cycle later
        trans.prdata  = vif.cb_mon.prdata;
        trans.pslverr = vif.cb_mon.pslverr;

        if (collect_enable) observed.push_back(trans);

        if (sb != null) begin
          if (trans.pwrite === 1'b1) begin
            monitor_writes++;
            sb.process_write(trans);
          end else begin
            monitor_reads++;
            sb.process_read(trans);
          end
        end
      end
    end
  endtask

  function void clear_collection();
    observed.delete();
  endfunction

  function void print_report();
    $display("[QSPI_MON STATS] Read transfers: %0d, Write transfers: %0d, Total: %0d",
             monitor_reads, monitor_writes, monitor_reads + monitor_writes);
  endfunction

  function int get_read_count();
    return monitor_reads;
  endfunction

  function int get_write_count();
    return monitor_writes;
  endfunction

endclass

