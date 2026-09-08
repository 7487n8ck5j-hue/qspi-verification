// =========================================================================
// TEST 11: External DLL Loopback (QSPI-PHY-SDR-11)
// Comprehensive validation of TX-then-RX mode, sequential half-duplex 
// loopback buffering, and strict CDC-aware APB polling.
// =========================================================================

task automatic run_test_11(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val; 
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 11: External DLL Loopback (QSPI-PHY-SDR-11)");
    $display(" Target: Validate half-duplex sequential data sampling loopback.");
    $display("=======================================================================\n");

    // We use fork..join_any to run the APB Master and the hardware loopback simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Sequential Hardware Loopback Buffer
        // ---------------------------------------------------------
        begin : external_loopback_buffer
            reg [31:0] loopback_reg;
            forever begin
                @(negedge vif.CS_n);
                
                // PHASE 1: Record Master's TX Data (32 cycles)
                for (int i=0; i<32; i++) begin
                    @(posedge vif.CLK);
                    loopback_reg = {loopback_reg[30:0], vif.D0};
                end
                
                // PHASE 2: Playback Data to Master's RX Phase (32 cycles)
                // Wait for the master to transition from ST_TX to ST_RX
                @(negedge vif.CLK);
                for (int i=0; i<32; i++) begin
                    #1 vif.D1 <= loopback_reg[31]; // Drive data on negedge for master to sample on posedge
                    loopback_reg = {loopback_reg[30:0], 1'b0};
                    if (i < 31) @(negedge vif.CLK);
                end
                
                @(posedge vif.CS_n);
                #1 vif.D1 <= 1'bz;
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
            // FIX: Set Transfer Length to 31 (32 cycles) for BOTH the TX and RX phases
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Loading Loopback Payload ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h5A5A_C3C3; agt.send_write(tx); 

            $display("[INFO] --- STEP 3: Triggering TX-then-RX Mode ---");
            // FIX: Trigger TX-then-RX Mode (Bits 14:13 = 2'b10 -> 0x4000) + Start (Bit 0 = 1) = 0x4001
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; agt.send_write(tx); 
            
            // FIX: Proper CDC Delay & Polling Status Register (0x18) Bit 11
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; 
                agt.send_read(tx);
                @(posedge vif.pclk); 
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);
            
            $display("   [DEBUG] FSM returned to IDLE after %0d APB clock cycles.", timeout_ctr);

            $display("[INFO] --- STEP 4: Fetching captured data from RX FIFO ---");
            tx = new(); tx.paddr = 32'h08; 
            agt.send_read(tx);
            val = tx.prdata;
        end
    join_any
    
    // Safety cleanup: Kill background loopback and release the pin immediately
    disable fork; 
    vif.D1 <= 1'bz;

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] Hardware locked up during loopback test.\n");
        test_pass = 1'b0;
    end else if (val === 32'h5A5A_C3C3) begin
        $display("   [PASS] Loopback sampling verified cleanly without phase drift. Data: %h\n", val);
    end else begin
        $display("   [FAIL] Loopback data mismatch. Expected: 5A5AC3C3, Got: %h\n", val);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-SDR-11");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-SDR-11");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
