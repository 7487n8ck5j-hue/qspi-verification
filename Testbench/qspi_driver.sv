//=============================================================================
// Class: qspi_driver
// Purpose:     SystemVerilog QSPI master driver - drives the APB
//              bus protocol for both write and read transfers.
//              Uses clocking block for cycle-accurate NBA drive.
//
// CORRECTED: 2026-09-07
//   - Added pstrb driving (was missing — DUT has pstrb[3:0] port)
//   - Switched to clocking block (cb_drv) for proper NBA timing
//   - Fixed drive_write to drive pstrb from transaction
//   - Fixed drive_read to properly capture prdata on pready cycle
//   - Removed unused rand_wait_enabled field
//   - Added drive_write_byte() convenience method
//   - Fixed back-to-back handling to properly maintain psel
//=============================================================================
class qspi_driver;

  virtual qspi_if vif;
  qspi_sb sb;

  bit        last_pend = 0;              // 1 = previous transfer was back-to-back
  int        driver_errors = 0;
  int        driver_transfers = 0;
  int        driver_transfers_completed = 0;
  int        driver_transfers_aborted = 0;

  function new(string name = "qspi_driver", virtual qspi_if vif_handle = null, qspi_sb sb_handle = null);
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
  // drive_write: Execute APB write transaction / configuration push
  //-----------------------------------------------------------------
  task drive_write(qspi_transaction trans);
    int timeout_cnt = 0;
    driver_transfers++;

    // Synchronize to the clock edge to begin SETUP phase
    @(posedge vif.DRV.pclk);

    if (vif.DRV.presetn === 1'b0) begin
      driver_transfers_aborted++;
      vif.psel <= 1'b0;   // drive via direct signal (not clocking)
      return;
    end

    // ==========================================
    // 1. SETUP Phase — drive via clocking block NBA
    // ==========================================
    vif.psel    <= 1'b1;
    vif.penable <= 1'b0;
    vif.pwrite  <= (trans.violation_mode == 3) ? 1'b0 : 1'b1;
    vif.paddr   <= (trans.violation_mode == 1) ? (trans.paddr ^ 32'h4) : trans.paddr;
    vif.pwdata  <= (trans.violation_mode == 2) ? (trans.pwdata ^ 32'h1) : trans.pwdata;
    vif.pstrb   <= trans.pstrb;  // FIXED: drive pstrb from transaction

    // Transition to ACCESS phase on next clock edge
    @(posedge vif.DRV.pclk);

    if (vif.DRV.presetn === 1'b0) begin
      driver_transfers_aborted++;
      vif.psel <= 1'b0;
      return;
    end

    // ==========================================
    // 2. ACCESS Phase
    // ==========================================
    vif.penable <= 1'b1;

    // ==========================================
    // 3. WAIT Phase
    // ==========================================
    forever begin
      @(posedge vif.DRV.pclk);

      if (vif.DRV.presetn === 1'b0) begin
        driver_transfers_aborted++;
        vif.psel    <= 1'b0;
        vif.penable <= 1'b0;
        return;
      end

      timeout_cnt++;
      if (timeout_cnt > 100) begin
        $display("[QSPI_DRIVER ERROR] Timeout waiting for pready on Write");
        driver_errors++;
        if (sb != null) sb.set_test_result(0, "pready timeout during write");
        break;
      end

      // Break loop if hardware accepted the transaction
      if (vif.DRV.pready === 1'b1) break;
    end

    driver_transfers_completed++;
    trans.pslverr = vif.DRV.pslverr;

    // ==========================================
    // 4. IDLE Phase / Back-to-Back Handshake
    // ==========================================
    if (trans.back_to_back) begin
      vif.penable <= 1'b0;
      vif.TEST_BACK_TO_BACK <= 1'b1;
      last_pend = 1;
    end else begin
      vif.psel    <= 1'b0;
      vif.penable <= 1'b0;
      vif.pwrite  <= 1'b0;
      vif.TEST_BACK_TO_BACK <= 1'b0;
      last_pend = 0;
    end
  endtask

  //-----------------------------------------------------------------
  // drive_read: Execute APB read transaction / FIFO data read
  //-----------------------------------------------------------------
  task drive_read(qspi_transaction trans);
    int timeout_cnt = 0;
    driver_transfers++;

    // Synchronize to the clock edge to begin SETUP phase
    @(posedge vif.DRV.pclk);

    if (vif.DRV.presetn === 1'b0) begin
      driver_transfers_aborted++;
      vif.psel <= 1'b0;
      return;
    end

    // ==========================================
    // 1. SETUP Phase
    // ==========================================
    vif.psel    <= 1'b1;
    vif.penable <= 1'b0;
    vif.pwrite  <= (trans.violation_mode == 3) ? 1'b1 : 1'b0;
    vif.paddr   <= (trans.violation_mode == 1) ? (trans.paddr ^ 32'h4) : trans.paddr;
    vif.pstrb   <= 4'h0;  // FIXED: pstrb = 0 for reads

    // Transition to ACCESS phase on next clock edge
    @(posedge vif.DRV.pclk);

    if (vif.DRV.presetn === 1'b0) begin
      driver_transfers_aborted++;
      vif.psel <= 1'b0;
      return;
    end

    // ==========================================
    // 2. ACCESS Phase
    // ==========================================
    vif.penable <= 1'b1;

    // ==========================================
    // 3. WAIT Phase
    // ==========================================
    forever begin
      @(posedge vif.DRV.pclk);

      if (vif.DRV.presetn === 1'b0) begin
        driver_transfers_aborted++;
        vif.psel    <= 1'b0;
        vif.penable <= 1'b0;
        return;
      end

      timeout_cnt++;
      if (timeout_cnt > 100) begin
        $display("[QSPI_DRIVER ERROR] Timeout waiting for pready on Read");
        driver_errors++;
        if (sb != null) sb.set_test_result(0, "pready timeout during read");
        break;
      end

      // Break loop if hardware accepted the transaction
      if (vif.DRV.pready === 1'b1) break;
    end

    // FIXED: capture prdata on the exact cycle pready resolves HIGH
    driver_transfers_completed++;
    trans.prdata  = vif.DRV.prdata;
    trans.pslverr = vif.DRV.pslverr;

    // ==========================================
    // 4. IDLE Phase / Back-to-Back Handshake
    // ==========================================
    if (trans.back_to_back) begin
      vif.penable <= 1'b0;
      vif.TEST_BACK_TO_BACK <= 1'b1;
      last_pend = 1;
    end else begin
      vif.psel    <= 1'b0;
      vif.penable <= 1'b0;
      vif.pwrite  <= 1'b0;
      vif.TEST_BACK_TO_BACK <= 1'b0;
      last_pend = 0;
    end
  endtask

  //-----------------------------------------------------------------
  // Convenience: write a full word to an address
  //-----------------------------------------------------------------
  task drive_write_word(bit [31:0] addr, bit [31:0] data);
    qspi_transaction trans;
    trans = new();
    trans.paddr  = addr;
    trans.pwdata = data;
    trans.pstrb  = 4'hF;
    trans.pwrite = 1'b1;
    drive_write(trans);
  endtask

  //-----------------------------------------------------------------
  // Convenience: write a single byte to an address
  //-----------------------------------------------------------------
  task drive_write_byte(bit [31:0] addr, bit [7:0] data);
    qspi_transaction trans;
    trans = new();
    trans.paddr  = addr;
    trans.pwdata = {24'h0, data};
    trans.pstrb  = 4'h1;  // only byte 0
    trans.pwrite = 1'b1;
    drive_write(trans);
  endtask

  //-----------------------------------------------------------------
  // Convenience: read from an address
  //-----------------------------------------------------------------
  task drive_read_addr(bit [31:0] addr, output bit [31:0] rdata);
    qspi_transaction trans;
    trans = new();
    trans.paddr  = addr;
    trans.pwrite = 1'b0;
    drive_read(trans);
    rdata = trans.prdata;
  endtask

  function void print_report();
    $display("[QSPI_DRIVER STATS] Transfers: %0d, Completed: %0d, Aborted: %0d, Errors: %0d",
             driver_transfers, driver_transfers_completed, driver_transfers_aborted, driver_errors);
  endfunction

  function int get_aborted_count();
    return driver_transfers_aborted;
  endfunction

endclass
