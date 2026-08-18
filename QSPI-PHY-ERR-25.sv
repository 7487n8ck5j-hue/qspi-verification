// =========================================================================
// TEST 25: Polling Expiration Timeout (QSPI-PHY-ERR-25)
// Comprehensive diagnostic verification of the hardware watchdog timer,
// consolidated status vector confirmation, and forced FSM abort mechanics.
// =========================================================================

task automatic run_test_25(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] irq_status;
    int timeout_ctr = 0; 
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 25: Polling Expiration Timeout (QSPI-PHY-ERR-25)");
    $display(" Target: Validate hardware polling timeout and interrupt vectors");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master & Strict Expiration Limit ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
    
    // Write the massive transfer length to 0x10 (XFERLEN_REG)
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_1000; agt.send_write(tx); 

    // Bind strict transaction expiration limit (Enable Timer [Bit 31] + Limit [Bits 15:0])
    tx = new(); tx.paddr = 32'h24; tx.pwdata = 32'h8000_004B; 
    agt.send_write(tx);

    $display("[INFO] --- STEP 2: Triggering Excessively Long Operation ---");
    // Start + Interrupts Enabled -> 0x0809
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0809; 
    agt.send_write(tx); 

    $display("[INFO] --- STEP 3: Monitoring Physical IRQ Pin ---");
    // Wait for the hardware interrupt to assert, bounded by a safe limit
    while (vif.irq == 1'b0 && timeout_ctr < 1000) begin
        @(posedge vif.pclk);
        timeout_ctr++;
    end

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] Simulator timed out. IRQ never asserted!");
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] IRQ Pin successfully asserted after %0d cycles.", timeout_ctr);
    end

    $display("[INFO] --- STEP 4: Validating Interrupt Status Vector ---");
    // FIX: Read the Status Register (0x18) instead of the unmapped 0x1C address.
    // The timeout vector is consolidated into Bit 4 of this register.
    tx = new(); tx.paddr = 32'h18; 
    agt.send_read(tx);
    irq_status = tx.prdata;
    
    $display("   [DEBUG] Status Register (0x18) Readback: %h", irq_status);
    
    // Check Bit 4 for the TIMEOUT_ERR flag
    if (irq_status[4] == 1'b1) begin
        $display("   [PASS] Watchdog efficiently terminated operation. Timeout vector (Bit 4) confirmed.");
    end else begin
        $display("   [FAIL] IRQ asserted, but Timeout flag (Bit 4) is missing! Ghost interrupt.");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 5: Verifying FSM Hardware Abort ---");
    // Check Status Register Bit 11 to ensure the FSM didn't hang and returned to IDLE
    if (irq_status[11] == 1'b0) begin
        $display("   [PASS] FSM successfully aborted the transaction and returned to IDLE.\n");
    end else begin
        $display("   [FAIL] FSM failed to abort! Busy bit [11] is still HIGH.\n");
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-ERR-25");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-ERR-25");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
