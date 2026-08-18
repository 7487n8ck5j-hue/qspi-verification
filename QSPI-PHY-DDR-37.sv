// =========================================================================
// TEST 37: DDR/DSPI Payload Extraction (QSPI-PHY-DDR-37)
// Comprehensive validation of Double Data Rate (DDR) payload extraction, 
// enforcing dual-edge clock synchronization, phase shifting, DAC enablement, and APB polling.
// =========================================================================

task automatic run_test_37(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val; 
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 37: DDR/DSPI Payload Extraction");
    $display(" Target: QSPI-PHY-DDR-37 | Validate payload extraction and bus alignment");
    $display("=======================================================================\n");

    // We use fork..join_any to run the APB Master and a Custom Quad-SPI Flash Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Custom Quad-SPI Mock Flash Slave (DDR Mode)
        // ---------------------------------------------------------
        begin : custom_quad_ddr_slave
            reg [31:0] payload = 32'hD5D5_5D5D;
            reg [3:0]  slave_drv = 4'b0000;
            forever begin
                @(negedge vif.CS_n);
                #1; // Delta-cycle safety
                
                // Shift out 8 nibbles (MSB first) across all 4 pins on BOTH clock edges (DDR)
                for (int i = 7; i >= 0; i--) begin 
                    slave_drv = (payload >> (i * 4)) & 4'hF; 
                    vif.D3 <= slave_drv[3]; 
                    vif.D2 <= slave_drv[2]; 
                    vif.D1 <= slave_drv[1]; 
                    vif.D0 <= slave_drv[0]; 
                    
                    if (i > 0) @(posedge vif.CLK or negedge vif.CLK);
                end
                
                @(posedge vif.CS_n); 
                #1; 
                // Release pins back to tb_top pullups
                vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz; 
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master APB Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring QSPI Master Architecture for DDR ---");
            // Clock Divider to 4 to account for CDC latency
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); 
            
            // The Transfer Length register ALWAYS expects bits, not clock cycles!
            // 32 bits total = 0x1F. The FSM will naturally execute this in 4 clock cycles via DDR.
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); 

            $display("[INFO] --- STEP 2: Triggering Quad-DDR RX Transaction (with DAC & Phase Shift) ---");
            // FIX: Enable DAC Enable (Bit 14 = 0x4000) + RX Sample Phase Shift (Bit 12 = 0x1000) 
            // + DDR Mode (Bit 11 = 0x0800) + Quad Enable (Bit 10 = 0x0400) + Reset Release (Bit 2 = 0x0004). 
            // DO NOT set the manual Start bit (Bit 0) when using the DAC pipeline! -> 0x5C04
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_5C04; agt.send_write(tx); 

            $display("[INFO] --- STEP 2.5: Kick-off Memory-Mapped Fetch ---");
            // Issue a memory-mapped read to trigger the DDR hardware burst pipeline
            tx = new(); tx.paddr = 32'h1000_0000; agt.send_read(tx);
            
            $display("[INFO] --- STEP 3: Actively Polling FSM Status ---");
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; 
                agt.send_read(tx);
                @(posedge vif.pclk); 
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 4: Extracting Payload from RX FIFO ---");
            // Read the extracted payload from RX FIFO (0x08)
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
        $display("   [FAIL] Hardware locked up during DDR/DSPI payload extraction test.\n");
        test_pass = 1'b0;
    end else if (val === 32'hD5D5_5D5D) begin
        $display("   [PASS] DDR/DSPI payload successfully extracted and aligned: %h\n", val);
    end else begin
        $display("   [FAIL] Data alignment corrupted. Expected: D5D55D5D, Got: %h\n", val);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-DDR-37");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-DDR-37");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
