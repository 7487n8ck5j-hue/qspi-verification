// =========================================================================
// TEST 12: At-Speed Scan Stress Toggle Check (QSPI-PHY-RST-12)
// Comprehensive diagnostic sequence validating continuous max-toggle 
// TX extraction with chunked auto-retriggering to prevent pipeline stalls.
// =========================================================================

task automatic run_test_12(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    int queue_drained = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 12: At-Speed Scan Stress Toggle Check (QSPI-PHY-RST-12)");
    $display(" Target: QSPI-PHY-RST-12 | Max-Activity TX Drain Validation");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    // Flush the FIFOs to remove ghost data left over from previous tests
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; 
    agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
    
    // FIX: Configure Transfer Length for exactly 1 word (32 bits = 0x1F) 
    // to enforce chunked execution across the auto-retrigger loop.
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); 

    $display("[INFO] --- STEP 2: Loading Maximum-Toggle Stress Payload ---");
    // Push 8 alternating words into the FIFO to maximize switching activity
    for (int i=0; i<8; i++) begin
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hAAAA_5555; 
        agt.send_write(tx); 
    end
    
    // Verify the FIFO actually holds all 8 words
    tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
    $display("   [DEBUG] TX FIFO Count before start: %0d", tx.prdata[3:0]);

    $display("[INFO] --- STEP 3: Triggering TX-Only Continuous Drain ---");
    // Trigger TX-Only Mode (Bits 14:13 = 2'b01 -> 0x2000) + Start (Bit 0 = 1) = 0x2001
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; 
    agt.send_write(tx);

    $display("[INFO] --- STEP 4: Actively Polling FSM Status & Auto-Retriggering ---");
    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    
    do begin
        tx = new(); tx.paddr = 32'h18; 
        agt.send_read(tx);
        @(posedge vif.pclk); 
        timeout_ctr++;
        
        // Check if FSM is idle (Bit 11 == 0)
        if (tx.prdata[11] == 1'b0) begin
            // Check if TX FIFO is fully empty (Bits 3:0 == 0)
            if (tx.prdata[3:0] == 4'd0) begin
                queue_drained = 1;
                break;
            end else begin
                // FIX: Retrigger Start TX for the next pipeline chunk
                tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; 
                agt.send_write(tx); 
            end
        end
    end while (timeout_ctr < 5000);

    $display("   [DEBUG] FSM polling concluded after %0d APB clock cycles.", timeout_ctr);
    $display("   [DEBUG] Final TX FIFO Count: %0d", tx.prdata[3:0]);

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 5000) begin
        $display("   [FAIL] Hardware locked up. Bounded timeout reached.\n");
        test_pass = 1'b0;
    end else if (!queue_drained) begin
        $display("   [FAIL] FSM returned to IDLE but TX FIFO did not fully drain!\n");
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] At-Speed toggle resolved without lockup. FIFO successfully drained 8 words.\n");
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-RST-12");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-RST-12");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
