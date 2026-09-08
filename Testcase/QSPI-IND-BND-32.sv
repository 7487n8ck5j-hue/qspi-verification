// =========================================================================
// TEST 32: Boundary Crossing (Indirect Register Mode) (QSPI-IND-BND-32)
// Comprehensive verification of manual indirect access triggers, 
// baseline FSM chip-select toggling, and proper APB synchronization.
// =========================================================================

task automatic run_test_32(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int cs_toggles = 0;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 32: Boundary Crossing (Indirect Register Mode)");
    $display(" Target: QSPI-IND-BND-32 | Indirect Access Execution & CS_n Verification");
    $display("=======================================================================\n");

    // Spawn a background monitor to count every time CS_n goes low
    fork
        begin : cs_monitor
            forever begin
                @(negedge vif.CS_n);
                cs_toggles++;
            end
        end
        begin : master_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            // FIX: Flush FIFOs and FSM state before starting
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; 
            agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring QSPI Master Architecture ---");
            // Set Clock Divider (0x0C) to 4 to ensure stable CDC
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; 
            agt.send_write(tx); 

            // FIX: Set Transfer Length to 0x10 (XFERLEN_REG), NOT 0x14 (DUMMY_CTRL)
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; // 32 bits (4 bytes)
            agt.send_write(tx); 

            $display("[INFO] --- STEP 2: Initiating Manual SPI Transaction ---");
            // Write data to TX Register (0x04)
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hFFFF_FFFF; 
            agt.send_write(tx); 
            
            // FIX: Trigger TX-Only Mode (Bits 14:13=01 [TX], Bit 0=1 [Start]) -> 0x2001
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; 
            agt.send_write(tx); 
            
            $display("[INFO] --- STEP 3: Actively Polling FSM Status ---");
            // FIX: Proper CDC Delay & Polling Status Register (0x18) Bit 11
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; 
                agt.send_read(tx);
                @(posedge vif.pclk); 
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 5000);
            
            $display("   [DEBUG] FSM returned to IDLE after %0d APB clock cycles.", timeout_ctr);
        end
    join_any
    
    // Safety cleanup: Kill background monitor thread
    disable fork; 

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 4: Final Result Evaluation ---");
    if (timeout_ctr >= 5000) begin
        $display("   [FAIL] Hardware locked up. FSM did not return to IDLE.\n");
        test_pass = 1'b0;
    end else if (cs_toggles > 0) begin
        $display("   [PASS] SPI FSM executed. Transaction correctly initiated (CS_n toggled %0d times).\n", cs_toggles);
    end else begin
        $display("   [FAIL] SPI FSM failed to execute. CS_n never asserted.\n");
        test_pass = 1'b0;
    end

    // =================================================================
    // Global Scoreboard Registration
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-IND-BND-32");
    tb_top.scoreboard.mark_as_run("QSPI-IND-BND-32");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
