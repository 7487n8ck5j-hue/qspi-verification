// =========================================================================
// TEST 40: Hardware HOLD Pin Suspension (QSPI-PHY-HSK-40)
// Comprehensive validation of D3 (HOLD_n) isolation during Single-SPI Mode,
// enforcing strict APB polling, correct CDC delays, and FIFO isolation.
// =========================================================================

task automatic run_test_40(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 40: Hardware HOLD Pin Suspension (QSPI-PHY-HSK-40)");
    $display(" Target: Validate D3 (HOLD_n) isolation during Single-SPI Mode");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    // FIX: Isolate the test environment by flushing previous states
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Architecture & Transfer Length ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
    
    // FIX: Configure Transfer Length for 1 word (32 bits = 0x1F)
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); 

    $display("[INFO] --- STEP 2: Loading TX FIFO ---");
    // Write data to TX register (0x04)
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h1234_5678; 
    agt.send_write(tx); 

    $display("[INFO] --- STEP 3: Triggering Single-SPI TX Transaction ---");
    // FIX: Trigger TX-Only Mode (Bits 14:13=01 [TX], Bit 0=1 [Start]) -> 0x2001
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; 
    agt.send_write(tx); 

    // Synchronize with the SPI clock domain out of APB to avoid delta-cycle misalignment
    repeat(4) @(posedge vif.pclk); 

    $display("[INFO] --- STEP 4: Validating D3 (HOLD_n) Pin State ---");
    if (vif.CS_n === 1'b0) begin
        if (vif.D3 === 1'b1 || vif.D3 === 1'bz) begin
            $display("   [PASS] D3 (HOLD_n) safely floating High-Z / Pulled HIGH during Single-SPI active phase.");
        end else begin
            $display("   [FAIL] D3 driven LOW! Transaction illegally suspended by Master.");
            test_pass = 1'b0;
        end
    end else begin 
        $display("   [FAIL] FSM failed to start. CS_n is not active.");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 5: Actively Polling FSM Status ---");
    // FIX: Poll Status Register (0x18) Bit 11 instead of Control Register (0x00) Bit 0
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; 
        agt.send_read(tx);
        @(posedge vif.pclk); 
        timeout_ctr++;
    end while (tx.prdata[11] == 1'b1 && timeout_ctr < 2000);

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 6: Final Result Evaluation ---");
    if (timeout_ctr >= 2000) begin
        $display("   [FAIL] Hardware locked up during transaction (Timeout reached).\n");
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] Transaction completed successfully. FSM returned to IDLE after %0d APB cycles.\n", timeout_ctr);
    end

    // =================================================================
    // Global Scoreboard Registration
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-HSK-40");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-HSK-40");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
