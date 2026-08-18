// =========================================================================
// TEST 04: Legacy SPI Mode FIFO Thresholds (TX) (QSPI-APB-LVL-04)
// Comprehensive diagnostic verification of TX DMA threshold limits, 
// FIFO population, and active hardware drain mechanics.
// =========================================================================

task automatic run_test_04(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 04: Legacy SPI Mode FIFO Thresholds (TX)");
    $display(" Target: QSPI-APB-LVL-04 | TX DMA Threshold & Drain Verification");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    // Flush the FIFOs to remove ghost data left over from Test 01
    // Write 1 to Bit 8 (Software Reset) -> 0x0100
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; 
    agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
    // Set Clock Divider to 4
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; 
    agt.send_write(tx); 
    
    // FIX: Set Transfer Length Register (0x10) to 31 (0x1F).
    // This equals 32 clock cycles (exactly 1 word). 
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; 
    agt.send_write(tx);

    $display("[INFO] --- STEP 2: Configuring DMA Control Register ---");
    // Set TX DMA threshold to 2 and enable TX DMA (Bit 0) -> 0x0201
    tx = new(); tx.paddr = 32'h28; tx.pwdata = 32'h0000_0201; 
    agt.send_write(tx); 
    
    // Diagnostic Readback
    tx = new(); tx.paddr = 32'h28; agt.send_read(tx);
    $display("   [DEBUG] DMA Control Reg (0x28) Readback: %h", tx.prdata);
    
    $display("[INFO] --- STEP 3: Populating TX FIFO ---");
    // Pre-fill the TX FIFO with EXACTLY 3 words. 
    for (int i=0; i<3; i++) begin
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hA0A0_0000; 
        agt.send_write(tx);
    end

    // Allow a few cycles for APB-to-FIFO CDC logic to settle
    repeat(3) @(posedge vif.pclk);
    $display("   [DEBUG] Internal TX FIFO Count before transfer: %0d", tb_top.dut.tx_fifo_cnt);
    
    $display("[INFO] --- STEP 4: Negative Check (Pre-Drain) ---");
    // Ensure the DMA request doesn't fire while FIFO > threshold (3 > 2)
    if (vif.tx_dma_req === 1'b0) begin
        $display("   [PASS] DMA Request correctly muted while FIFO (3) > Threshold (2).");
    end else begin
        $display("   [FAIL] DMA Request triggered too early! Expected LOW, got HIGH.");
        test_pass = 1'b0;
    end

    if (test_pass) begin
        $display("[INFO] --- STEP 5: Triggering SPI Transmission ---");
        // Trigger TX-Only Mode (Bit 13 = 1) + Start (Bit 0 = 1) -> 0x2001
        // This forces the FSM to pop exactly 1 word from the FIFO, dropping the count to 2.
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; 
        agt.send_write(tx);

        $display("[INFO] --- STEP 6: Active Polling for FIFO Drain & DMA Request ---");
        // Positive Check: Wait for the FIFO to drain and trigger the DMA request
        fork
            begin : check_request
                // Monitor for the request assertion
                wait(vif.tx_dma_req == 1'b1);
                $display("   [DEBUG] Internal TX FIFO Count at DMA trigger: %0d", tb_top.dut.tx_fifo_cnt);
                $display("   [PASS] TX DMA Level threshold successfully triggered as FIFO drained!");
            end
            begin : timeout_guard
                // Safety timeout synced to the clock
                repeat(500) @(posedge vif.pclk);
                $display("   [DEBUG] Timeout reached. Final Internal TX FIFO Count: %0d", tb_top.dut.tx_fifo_cnt);
                $display("   [DEBUG] RTL State Machine is stuck in STATE: %0d", tb_top.dut.state);
                $display("   [FAIL] Timeout: TX threshold request never triggered. FSM stalled.");
                test_pass = 1'b0;
            end
        join_any
        
        // Kill whichever branch didn't finish first
        disable fork;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-APB-LVL-04");
    tb_top.scoreboard.mark_as_run("QSPI-APB-LVL-04");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
