// =========================================================================
// TEST 18: STIG Memory Bank (QSPI-APB-SRD-18)
// Comprehensive validation of extended read transfers (>8 bytes) using 
// sequential RX triggers, proper CDC delays, and strict Status Register polling.
// =========================================================================

task automatic run_test_18(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 18: STIG Memory Bank (QSPI-APB-SRD-18)");
    $display(" Target: Validate extended read transfers (>8 Bytes)");
    $display("=======================================================================\n");

    // We use fork..join_any to run the APB Master and a Custom Toggling Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Custom Safe Mock Flash Slave
        // ---------------------------------------------------------
        begin : custom_safe_slave
            reg slave_D1_val = 1'b0;
            forever begin
                @(negedge vif.CS_n);
                #1; // Delta-cycle safety
                
                while (vif.CS_n == 1'b0) begin
                    @(negedge vif.CLK);
                    #1;
                    slave_D1_val = ~slave_D1_val;
                    vif.D1 <= slave_D1_val; 
                end
                
                #1; vif.D1 <= 1'bz; // Drive High-Z
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master APB Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); // Transfer Length (32 cycles / 4 bytes)

            $display("[INFO] --- STEP 2: Initiating Extended Transfer Sequence (3 words) ---");
            // Issue 3 consecutive RX transactions
            for (int i=0; i<3; i++) begin
                $display("   [DEBUG] Triggering RX Transaction %0d/3", i+1);
                // Trigger RX-Only Mode (0x0001)
                tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; 
                agt.send_write(tx);
                
                // FIX: Proper CDC Delay & Polling Status Register (0x18) Bit 11
                repeat(2) @(posedge vif.pclk);
                timeout_ctr = 0;
                do begin
                    tx = new(); tx.paddr = 32'h18; 
                    agt.send_read(tx);
                    @(posedge vif.pclk); 
                    timeout_ctr++;
                end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

                if (timeout_ctr >= 1000) begin
                    $display("   [FAIL] Timeout reached during transaction %0d!", i+1);
                    test_pass = 1'b0;
                    break;
                end
            end
        end
    join_any
    
    // Safety cleanup: Kill background slave and release pin immediately
    disable fork; 
    vif.D1 <= 1'bz; 

    $display("[INFO] --- STEP 3: Checking RX FIFO Depth ---");
    repeat(3) @(posedge vif.pclk);
    $display("   [DEBUG] Internal RX FIFO Count: %0d", tb_top.dut.rx_fifo_cnt);

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    if (!test_pass) begin
        $display("   [FAIL] Test aborted early due to timeout errors.\n");
    end else if (tb_top.dut.rx_fifo_cnt == 4'd3) begin
        $display("   [PASS] Extended transfer accumulated correctly in memory bank (3 words).\n");
    end else begin
        $display("   [FAIL] Internal queue did not hold expected depth. Got: %d\n", tb_top.dut.rx_fifo_cnt);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-APB-SRD-18");
    tb_top.scoreboard.mark_as_run("QSPI-APB-SRD-18");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
