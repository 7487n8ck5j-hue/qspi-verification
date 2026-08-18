// =========================================================================
// TEST 03: Status Register Polling (WIP Check) (QSPI-PHY-POL-03)
// Comprehensive diagnostic sequence validating iterative SPI reads, 
// WIP (Write-In-Progress) bit extraction, and APB-to-SPI clock domain sync.
// =========================================================================

task automatic run_test_03(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int poll_count = 0;
    logic [31:0] val = 32'h0000_0001; 
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 03: Status Register Polling (WIP Check)");
    $display(" Target: QSPI-PHY-POL-03 | Iterative FSM Polling & Payload Extraction");
    $display("=======================================================================\n");

    // We use fork..join_any to run the Master APB polling and the Custom Slave response simultaneously
    fork
        // ---------------------------------------------------------
        // THREAD 1: Custom Mock Slave (Simulates the WIP bit)
        // ---------------------------------------------------------
        begin : custom_mock_slave
            forever begin
                @(negedge vif.CS_n);
                #1; // Delta-cycle safety
                // Shift out 8 bits. Simulate WIP (Bit 0) being HIGH for the first 3 polls.
                for (int i=7; i>=0; i--) begin 
                    if (i == 0 && poll_count < 3) begin
                        vif.D1 <= 1'b1;
                    end else begin
                        vif.D1 <= 1'b0;
                    end
                    
                    if (i > 0) @(negedge vif.CLK);
                end
                poll_count++;
                @(posedge vif.CS_n); 
                #1;
                vif.D1 <= 1'bz; // Return bus to High-Z
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master Polling Sequence
        // ---------------------------------------------------------
        begin : master_apb_polling
            $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
            // FIX: Must configure Clock Divider and Transfer Length to prevent 0-length FSM locks.
            // Clock Divider = 4
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); 
            // Transfer Length = 1 Byte (8 bits for a standard Status Register read)
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0001; agt.send_write(tx);
            
            $display("[INFO] --- STEP 2: Initiating Polling Loop ---");
            // Keep polling via APB as long as the WIP bit is 1, up to 50 attempts
            while (val[0] == 1'b1 && timeout_ctr < 50) begin
                
                $display("   [DEBUG] Polling Attempt %0d...", timeout_ctr + 1);
                
                // 1. Trigger the SPI Read transaction
                tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; 
                agt.send_write(tx); 
                
                // FIX: Allow CDC propagation delay before checking the FSM active status
                repeat(10) @(posedge vif.pclk);

                // 2. Wait for the QSPI hardware FSM to return to idle
                do begin
                    tx = new(); tx.paddr = 32'h00; 
                    agt.send_read(tx);
                    @(posedge vif.pclk);
                end while (tx.prdata[0] != 1'b0);

                // 3. Read the fetched data from the RX FIFO (0x08)
                tx = new(); tx.paddr = 32'h08; 
                agt.send_read(tx);
                val = tx.prdata;
                
                $display("   [DEBUG] Status Register Readback: %h (WIP = %b)", val, val[0]);
                timeout_ctr++;
            end
        end
    join_any 
    
    // Safety cleanup: Kill slave thread and release bus
    disable fork; 
    vif.D1 <= 1'bz; 

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    if (val[0] == 1'b0 && timeout_ctr > 0 && timeout_ctr < 50) begin
        $display("[INFO] --- STEP 3: Evaluation ---");
        $display("   [PASS] Flash READY. Sequence exited cleanly after %0d polls.\n", timeout_ctr);
    end else begin
        $display("[INFO] --- STEP 3: Evaluation ---");
        $display("   [FAIL] Polling loop failed or timed out. Final Status Reg: %h, Polls: %0d\n", val, timeout_ctr);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-POL-03");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-POL-03");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
