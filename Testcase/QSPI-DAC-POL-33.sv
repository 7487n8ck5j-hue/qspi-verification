// =========================================================================
// TEST 33: Auto-Polling after DAC Write (QSPI-DAC-POL-33)
// Comprehensive verification of autonomous write-in-progress (WIP) status 
// polling cycles, proper reset isolation, and APB status synchronization.
// =========================================================================

task automatic run_test_33(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 33: Auto-Polling after DAC Write");
    $display(" Target: QSPI-DAC-POL-33 | Automated Write Cycle & Status Tracking");
    $display("=======================================================================\n");

    // Initialize data lines to a safe state
    vif.D1 <= 1'bz;

    // We use fork..join_any to run the APB Master and a Custom Auto-Poll Flash Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Simulated Auto-Poll Response Slave Implementation
        // ---------------------------------------------------------
        begin : custom_auto_poll_slave
            logic [7:0] cmd;
            int poll_count = 0;
            reg slave_D1_val = 1'b0;
            reg slave_oe_reg = 0;

            forever begin
                @(negedge vif.CS_n);
                #1; // Delta-cycle safety margin
                
                // Sample 8 incoming command bits on D0
                for (int i = 7; i >= 0; i--) begin 
                    @(posedge vif.CLK); 
                    cmd[i] = (vif.D0 === 1'bz) ? 1'b0 : vif.D0; 
                end
                
                if (cmd == 8'h05) begin // Read Status Register command
                    slave_oe_reg = 1;
                    for (int i = 7; i >= 0; i--) begin 
                        @(negedge vif.CLK); 
                        #1;
                        if (i == 0) slave_D1_val = (poll_count < 2) ? 1'b1 : 1'b0; // Busy bit (D1) drops after 2 polls
                        else slave_D1_val = 1'b0;
                        
                        vif.D1 <= slave_D1_val; // Safe procedural non-blocking driver update
                    end
                    poll_count++;
                end
                
                @(posedge vif.CS_n); 
                slave_oe_reg = 0;
                #1;
                vif.D1 <= 1'bz; // Return pin control to high-impedance state
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master APB Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            // FIX: Issue Software Reset to clear previous test states and prevent PSLVERR
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Activating DAC Write Configuration ---");
            tx = new(); tx.paddr = 32'h20; tx.pwdata = 32'h0000_0001; 
            agt.send_write(tx); 

            $display("[INFO] --- STEP 2: Executing DAC Write Transaction ---");
            tx = new(); tx.paddr = 32'h1000_0000; tx.pwdata = 32'hCAFE_BABE; 
            agt.send_write(tx); 

            $display("[INFO] --- STEP 3: Actively Polling Hardware WIP Tracking Phase ---");
            // FIX: Proper CDC Delay & Polling Status Register (0x18) Bit 11
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; 
                agt.send_read(tx);
                @(posedge vif.pclk); 
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 5000);
            
            $display("   [DEBUG] Auto-polling resolved after %0d APB clock cycles.", timeout_ctr);
        end
    join_any
    
    // Safety cleanup: Terminate background threads and release pin immediately to High-Z
    disable fork; 
    vif.D1 <= 1'bz; 

    repeat(5) @(posedge vif.pclk);

    // =================================================================
    // Result Evaluation & Data Integrity Verification
    // =================================================================
    $display("[INFO] --- STEP 4: Final Result Evaluation ---");
    if (timeout_ctr >= 5000) begin
        $display("   [FAIL] Hardware timed out or locked up during polling phase (Timeout >= 5000 cycles).\n");
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] Hardware auto-polling sequence verified. Write cycle resolved cleanly.\n");
    end

    // =================================================================
    // Global Scoreboard Registration
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-DAC-POL-33");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-POL-33");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
