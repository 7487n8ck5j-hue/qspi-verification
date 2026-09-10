//=============================================================================
// Class: qspi_driver
// Purpose:     APB3 master driver for the QSPI controller.
//
// REVISION 2026-09-08:
//   [FIX-A] All bus activity now goes through the cb_drv clocking block. The
//           previous version declared a clocking block but drove raw interface
//           signals and sampled plain modport members, so the clocking block
//           was dead code and every access relied on hand-rolled timing.
//           Sampling through cb_drv gives prdata as it was stable during the
//           ACCESS phase, which is the whole point.
//   [FIX-B] drive_read now captures prdata on the cycle where pready is
//           sampled high, before PSEL/PENABLE are dropped. The old code was
//           reading after the DUT's combinational prdata had already collapsed
//           to zero.
//   [FIX-C] A pready timeout is no longer counted as a completed transfer.
//           Previously the code broke out of the wait loop on timeout and then
//           unconditionally incremented driver_transfers_completed and
//           sampled data, so a hung bus still looked like a clean transfer.
//   [FIX-D] The driver no longer forwards transactions to the scoreboard - the
//           monitor is the single source of truth. This removes the double
//           counting that came from agent.send_* and the monitor both calling
//           sb.process_*.
//   [FIX-E] Back-to-back handling keeps PSEL asserted and goes straight into
//           the next SETUP phase, and TEST_BACK_TO_BACK is cleared when the
//           burst ends so interface assertions stay meaningful.
//=============================================================================
class qspi_driver;

  virtual qspi_if vif;
  qspi_sb sb;

  int driver_errors = 0;
  int driver_transfers = 0;
  int driver_transfers_completed = 0;
  int driver_transfers_aborted = 0;
  int driver_timeouts = 0;

  localparam int PREADY_TIMEOUT = 100;

  // NOTE: vif_handle deliberately has no default value. Verilator (and some
  // other tools) reject `virtual qspi_if h = null` because the null literal is
  // not an interface type. Every construction site passes a real handle.
  function new(string name = "qspi_driver", virtual qspi_if vif_handle,
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
  // Park the bus in IDLE
  //-----------------------------------------------------------------
  task idle_bus();
    vif.cb_drv.psel    <= 1'b0;
    vif.cb_drv.penable <= 1'b0;
    vif.cb_drv.pwrite  <= 1'b0;
    vif.cb_drv.pstrb   <= 4'hF;
    vif.cb_drv.TEST_BACK_TO_BACK <= 1'b0;
  endtask

  //-----------------------------------------------------------------
  // Common APB transfer engine (used by both read and write)
  //   returns 1 on a completed transfer, 0 on abort/timeout
  //-----------------------------------------------------------------
  local task automatic apb_xfer(qspi_transaction trans, bit is_write, output bit ok);
    int timeout_cnt = 0;
    bit [31:0] addr_drv;
    bit        wr_drv;
    bit [31:0] wdata_drv;

    ok = 0;
    driver_transfers++;

    // Violation injection (used by protocol-error tests)
    addr_drv  = (trans.violation_mode == 1) ? (trans.paddr ^ 32'h4) : trans.paddr;
    wdata_drv = (trans.violation_mode == 2) ? (trans.pwdata ^ 32'h1) : trans.pwdata;
    wr_drv    = (trans.violation_mode == 3) ? ~is_write : is_write;

    // ------------------------------------------------------------------
    // SETUP phase. If the previous transfer ended back-to-back, PSEL is
    // already high and we drive the new address straight into SETUP.
    // ------------------------------------------------------------------
    @(vif.cb_drv);
    if (vif.presetn === 1'b0) begin
      driver_transfers_aborted++;
      idle_bus();
      return;
    end

    vif.cb_drv.psel    <= 1'b1;
    vif.cb_drv.penable <= 1'b0;
    vif.cb_drv.pwrite  <= wr_drv;
    vif.cb_drv.paddr   <= addr_drv;
    // pstrb must be 0 for reads and the requested value for writes
    vif.cb_drv.pstrb   <= is_write ? trans.pstrb : 4'h0;
    if (is_write) vif.cb_drv.pwdata <= wdata_drv;

    // ------------------------------------------------------------------
    // ACCESS phase
    // ------------------------------------------------------------------
    @(vif.cb_drv);
    if (vif.presetn === 1'b0) begin
      driver_transfers_aborted++;
      idle_bus();
      return;
    end
    vif.cb_drv.penable <= 1'b1;

    // ------------------------------------------------------------------
    // Wait for pready, then sample response IN THE SAME CYCLE.
    // cb_drv inputs use a #1step skew, so at this point cb_drv.prdata is the
    // value that was stable through the ACCESS phase - the correct capture.
    // ------------------------------------------------------------------
    forever begin
      @(vif.cb_drv);

      if (vif.presetn === 1'b0) begin
        driver_transfers_aborted++;
        idle_bus();
        return;
      end

      if (vif.cb_drv.pready === 1'b1) begin
        // [FIX-B] capture before dropping the command phase
        trans.pready  = 1'b1;
        trans.prdata  = vif.cb_drv.prdata;
        trans.pslverr = vif.cb_drv.pslverr;
        driver_transfers_completed++;
        ok = 1;
        break;
      end

      timeout_cnt++;
      if (timeout_cnt > PREADY_TIMEOUT) begin
        // [FIX-C] a timeout is a failure, not a completed transfer
        $display("[QSPI_DRIVER ERROR] Timeout waiting for pready on %s to 0x%0h",
                 is_write ? "WRITE" : "READ", addr_drv);
        driver_errors++;
        driver_timeouts++;
        trans.pready = 1'b0;
        if (sb != null) sb.set_test_result(0, "pready timeout");
        idle_bus();
        return;
      end
    end

    // ------------------------------------------------------------------
    // Close out: either hold PSEL for a back-to-back burst or go idle
    // ------------------------------------------------------------------
    if (trans.back_to_back) begin
      vif.cb_drv.penable <= 1'b0;        // PSEL stays high
      vif.cb_drv.TEST_BACK_TO_BACK <= 1'b1;
    end else begin
      idle_bus();
    end
  endtask

  //-----------------------------------------------------------------
  // Public API
  //-----------------------------------------------------------------
  task drive_write(qspi_transaction trans);
    bit ok;
    trans.pwrite = 1'b1;
    apb_xfer(trans, 1'b1, ok);
  endtask

  task drive_read(qspi_transaction trans);
    bit ok;
    trans.pwrite = 1'b0;
    apb_xfer(trans, 1'b0, ok);
  endtask

  //-----------------------------------------------------------------
  // Convenience helpers
  //-----------------------------------------------------------------
  task drive_write_word(bit [31:0] addr, bit [31:0] data);
    qspi_transaction trans = new();
    trans.paddr  = addr;
    trans.pwdata = data;
    trans.pstrb  = 4'hF;
    drive_write(trans);
  endtask

  task drive_write_strb(bit [31:0] addr, bit [31:0] data, bit [3:0] strb);
    qspi_transaction trans = new();
    trans.paddr  = addr;
    trans.pwdata = data;
    trans.pstrb  = strb;
    drive_write(trans);
  endtask

  task drive_write_byte(bit [31:0] addr, bit [7:0] data);
    qspi_transaction trans = new();
    trans.paddr  = addr;
    trans.pwdata = {24'h0, data};
    trans.pstrb  = 4'h1;               // only byte lane 0
    drive_write(trans);
  endtask

  task drive_read_addr(bit [31:0] addr, output bit [31:0] rdata);
    qspi_transaction trans = new();
    trans.paddr = addr;
    drive_read(trans);
    rdata = trans.prdata;
  endtask

  task drive_read_full(bit [31:0] addr, output bit [31:0] rdata, output bit slverr);
    qspi_transaction trans = new();
    trans.paddr = addr;
    drive_read(trans);
    rdata  = trans.prdata;
    slverr = trans.pslverr;
  endtask

  // Wait until the controller is no longer busy (STATUS bit 20), bounded.
  task wait_not_busy(int max_cycles = 20000);
    bit [31:0] st;
    int n = 0;
    forever begin
      drive_read_addr(32'h18, st);
      if (st[20] === 1'b0) break;
      n++;
      if (n > max_cycles) begin
        $display("[QSPI_DRIVER ERROR] wait_not_busy timed out");
        driver_errors++;
        if (sb != null) sb.set_test_result(0, "controller stuck busy");
        break;
      end
    end
  endtask

  function void print_report();
    $display("[QSPI_DRIVER STATS] Transfers: %0d, Completed: %0d, Aborted: %0d, Timeouts: %0d, Errors: %0d",
             driver_transfers, driver_transfers_completed,
             driver_transfers_aborted, driver_timeouts, driver_errors);
  endfunction

  function int get_aborted_count();
    return driver_transfers_aborted;
  endfunction

endclass

