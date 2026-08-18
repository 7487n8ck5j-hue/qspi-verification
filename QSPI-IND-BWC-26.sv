// =========================================================================
// TEST 26: INDAC Bulk Write Configuration (QSPI-IND-BWC-26)
// Comprehensive validation of Indirect Access Controller (INDAC) FIFO 
// drainage using front-door APB polling, chunked TX-Only mode execution, 
// and proper auto-retriggering for bulk transfers.
// =========================================================================

task automatic run_test_26(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    int queue_drained = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 26: INDAC Bulk Write Configuration");
    $display(" Target: Validate Indirect Access Controller (INDAC) FIFO drainage.");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master & INDAC Boundaries ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
    
    // FIX: Configure Transfer Length for exactly 1 word (32 bits = 0x1F) 
    // to enforce chunked execution across the auto-retrigger loop.
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); 

    $display("[INFO] --- STEP 2: Loading 8 words into the TX FIFO ---");
    for (int i=0; i<8; i++) begin
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hA1A1_0000 + i; 
        agt.send_write(tx); 
    end

    // Front-door check of FIFO depth before start
    tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
    $display("   [DEBUG] TX FIFO Count before start: %0d", tx.prdata[3:0]);

    $display("[INFO] --- STEP 3: Triggering INDAC Bulk TX Transfer ---");
    // Trigger TX-Only Mode (Bits 14:13=01 [TX], Bit 0=1 [Start]) -> 0x2001
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; 
    agt.send_write(tx); 

    $display("[INFO] --- STEP 4: Front-Door Status Polling & Auto-Retrigger ---");
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
                // FIX: Retrigger Start TX for the next INDAC chunk
                tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; 
                agt.send_write(tx); 
            end
        end
    end while (timeout_ctr < 5000);

    $display("   [DEBUG] Polling concluded after %0d APB clock cycles.", timeout_ctr);
    if (queue_drained == 0) begin
        $display("   [DEBUG] Final Status Reg (0x18): %h (Busy=%b, TX_FIFO=%0d)", tx.prdata, tx.prdata[11], tx.prdata[3:0]);
    end

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 5000) begin
        $display("   [FAIL] Hardware locked up. Queue did not drain within timeout limit.\n");
        test_pass = 1'b0;
    end else if (queue_drained) begin
        $display("   [PASS] INDAC bulk payload fully transmitted. TX FIFO drained successfully.\n");
    end else begin
        $display("   [FAIL] FSM returned to IDLE but TX FIFO did not fully drain!\n");
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-IND-BWC-26");
    tb_top.scoreboard.mark_as_run("QSPI-IND-BWC-26");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
