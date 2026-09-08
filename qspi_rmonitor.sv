//=============================================================================
// Class: qspi_monitor (Read Monitor)
// Purpose:     SystemVerilog QSPI read monitor - passively observes
//              read transfers on the APB bus interface.
//
// CORRECTED: 2026-09-07
//   - This is the SINGLE corrected copy (original had 3 duplicate definitions)
//   - Fixed monitor to also observe write transfers (not just reads)
//   - Fixed #0 delay — replaced with proper @(posedge) sampling
//   - Fixed infinite loop risk in wait-for-penable-deassert
//   - Added timeout protection for penable de-assertion wait
//=============================================================================
class qspi_monitor;

  virtual qspi_if vif;
  qspi_sb sb;
  int monitor_reads = 0;
  int monitor_writes = 0;   // FIXED: added write counter

  function new(string name = "qspi_monitor", virtual qspi_if vif_handle = null, qspi_sb sb_handle = null);
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
  // run: forever loop observing ALL transfers (reads AND writes)
  //-----------------------------------------------------------------
  task run();
    qspi_transaction trans;
    int wait_cycle_count;

    if (vif == null) begin
      $display("[QSPI_RMON ERROR] Virtual interface handle is null!");
      return;
    end

    forever begin
      trans = new();
      @(posedge vif.MON.pclk);

      if (vif.MON.presetn === 1'b0) begin
        @(posedge vif.MON.pclk);  // skip cycle after reset
        continue;
      end

      // Wait until psel & penable (any transfer — read or write)
      wait_cycle_count = 0;
      while (!vif.MON.psel || !vif.MON.penable) begin
        wait_cycle_count++;
        if (wait_cycle_count > 10000) begin
          $display("[QSPI_RMON ERROR] Timeout waiting for transfer start");
          break;
        end
        @(posedge vif.MON.pclk);
        if (vif.MON.presetn === 1'b0) break;
      end
      if (vif.MON.presetn === 1'b0) continue;
      if (wait_cycle_count > 10000) continue;

      // Capture transaction info at ACCESS phase
      trans.presetn = vif.MON.presetn;
      trans.paddr   = vif.MON.paddr;
      trans.pwrite  = vif.MON.pwrite;
      trans.pwdata  = vif.MON.pwdata;  // capture write data for writes
      trans.pstrb   = vif.MON.pstrb;   // FIXED: capture pstrb

      // Wait for pready (slave provides data/response)
      wait_cycle_count = 0;
      while (!vif.MON.pready) begin
        wait_cycle_count++;
        if (wait_cycle_count > 100) begin
          $display("[QSPI_RMON ERROR] Timeout waiting for pready");
          break;
        end
        @(posedge vif.MON.pclk);
        if (vif.MON.presetn === 1'b0) break;
      end
      if (vif.MON.presetn === 1'b0) continue;

      // FIXED: sample on the next posedge to let DUT NBA settle
      // (replaced #0 with proper clock edge sampling)
      @(posedge vif.MON.pclk);

      trans.pready  = vif.MON.pready;
      trans.prdata  = vif.MON.prdata;
      trans.pslverr = vif.MON.pslverr;

      // Route to scoreboard based on direction
      if (sb != null) begin
        if (trans.pwrite) begin
          monitor_writes++;
          sb.process_write(trans);
        end else begin
          monitor_reads++;
          sb.process_read(trans);
        end
      end

      // Wait for penable de-assertion to avoid re-detecting the same transfer
      // FIXED: added timeout protection
      wait_cycle_count = 0;
      while (vif.MON.psel && vif.MON.penable) begin
        wait_cycle_count++;
        if (wait_cycle_count > 100) begin
          $display("[QSPI_RMON WARN] Timeout waiting for penable de-assertion");
          break;
        end
        @(posedge vif.MON.pclk);
        if (vif.MON.presetn === 1'b0) break;
      end
    end
  endtask

  function void print_report();
    $display("[QSPI_RMON STATS] Read transfers: %0d, Write transfers: %0d, Total: %0d",
             monitor_reads, monitor_writes, monitor_reads + monitor_writes);
  endfunction

  function int get_read_count();
    return monitor_reads;
  endfunction

  function int get_write_count();
    return monitor_writes;
  endfunction

endclass

