// =========================================================================
// TEST 30: Maximum Bandwidth Fetch Config (QSPI-PHY-MBW-30)
// Comprehensive validation of Quad-SPI maximum bandwidth data fetch,
// enforcing strict APB polling, 1:1 clock ratios, phase shifting, and reset logic.
// =========================================================================

task automatic run_test_30(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val; 
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 30: Maximum Bandwidth Fetch Config (QSPI-PHY-MBW-30)");
    $display(" Target: Validate Quad-SPI data fetch at maximum physical bandwidth");
    $display("=======================================================================\n");

    // We use fork..join_any to run the APB Master and a Custom Quad-SPI Flash Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Custom Quad-SPI Mock Flash Slave (1:1 Zero-Latency)
        // ---------------------------------------------------------
        begin : custom_quad_mbw_slave
            reg [31:0] payload = 32'hFAC0_FAC0;
            reg [3:0]  slave_drv = 4'b0000;
            forever begin
                @(negedge vif.CS_n);
                
                // At 1:1 clock ratio, remove all intermediate delays (#1) inside the loop 
                // so the mock slave instantly matches the master's max-bandwidth edge capture.
                for (int i=7; i>=0; i--) begin 
                    slave_drv = (payload >> (i*4)) & 4'hF; 
                    vif.D3 <= slave_drv[3]; 
                    vif.D2 <= slave_drv[2]; 
                    vif.D1 <= slave_drv[1]; 
                    vif.D0 <= slave_drv[0]; 
                    
                    if (i > 0) @(negedge vif.CLK);
                end
                
                @(posedge vif.CS_n); 
                // Release the pins back to the default tb_top pullups
                vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz; 
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master APB Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            // Flush the FIFOs to remove ghost data left over from previous tests
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring QSPI Master Architecture ---");
            // Configure Clock Divider to 0x00 for Maximum Physical Bandwidth
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0000; agt.send_write(tx); 
            
            // Transfer Length expects bits. 32-bits = 0x1F.
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); 

            $display("[INFO] --- STEP 2: Triggering Quad-SPI RX Mode (with Phase Shift) ---");
            // FIX: Restore Phase Shift and remove the invalid TX-Only mode bit! 
            // RX Sample Phase Shift (Bit 12 = 0x1000) + Quad Enable (Bit 10 = 0x0400) + Reset Release (Bit 2 = 0x0004) + Start (Bit 0 = 0x0001). -> 0x1405
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_1405; agt.send_write(tx); 
            
            $display("[INFO] --- STEP 3: Actively Polling FSM Status ---");
            // Proper CDC Delay & Polling Status Register (0x18) Bit 11
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; 
                agt.send_read(tx);
                @(posedge vif.pclk); 
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("   [DEBUG] FSM returned to IDLE after %0d APB clock cycles.", timeout_ctr);

            $display("[INFO] --- STEP 4: Extracting Maximum Bandwidth Payload ---");
            // Read the fetched maximum bandwidth payload from RX FIFO (0x08)
            tx = new(); tx.paddr = 32'h08; 
            agt.send_read(tx);
            val = tx.prdata;
        end
    join_any
    
    // Safety cleanup: Kill background slave and release pins immediately
    disable fork; 
    vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz; 

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] Hardware locked up during maximum bandwidth fetch test.\n");
        test_pass = 1'b0;
    end else if (val === 32'hFAC0_FAC0) begin
        $display("   [PASS] Maximum bandwidth fetch stabilized and aligned perfectly: %h\n", val);
    end else begin
        $display("   [FAIL] Clock generation fractured at max bandwidth. Expected: FAC0FAC0, Got: %h\n", val);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-MBW-30");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-MBW-30");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
