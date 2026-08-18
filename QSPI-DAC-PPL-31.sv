// =========================================================================
// TEST 31: DAC Prediction Pipeline Configuration (QSPI-DAC-PPL-31)
// Comprehensive verification of non-predictive cache fetch architecture, 
// quad-SPI flash slave serialization, and DAC memory-mapped direct reads.
// =========================================================================

task automatic run_test_31(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val; 
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 31: DAC Prediction Pipeline Configuration");
    $display(" Target: QSPI-DAC-PPL-31 | Non-Predictive Data Fetch & Pipeline Verification");
    $display("=======================================================================\n");

    // Initialize quad-SPI data interface pins to high-impedance state
    vif.D3 <= 1'bz; 
    vif.D2 <= 1'bz; 
    vif.D1 <= 1'bz; 
    vif.D0 <= 1'bz;

    // We use fork..join_any to run the APB Master and a Custom Quad-SPI Flash Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Custom Quad-SPI Mock Flash Slave Implementation
        // ---------------------------------------------------------
        begin : custom_quad_dac_slave
            reg [31:0] payload = 32'hA1B2_C3D4;
            reg [3:0]  slave_drv = 4'b0000;
            
            forever begin
                @(negedge vif.CS_n);
                
                // Standard non-XIP DAC reads transmit an 8-bit instruction and 24-bit address.
                // We must wait exactly 32 clock cycles before driving the data payload to avoid bus collisions.
                repeat(32) @(negedge vif.CLK);
                #1; // Delta-cycle propagation safety margin
                
                // Shift out 8 nibbles (MSB first) across all 4 pins concurrently (Quad Mode)
                for (int i = 7; i >= 0; i--) begin 
                    slave_drv = (payload >> (i * 4)) & 4'hF; 
                    vif.D3 <= slave_drv[3]; 
                    vif.D2 <= slave_drv[2]; 
                    vif.D1 <= slave_drv[1]; 
                    vif.D0 <= slave_drv[0]; 
                    
                    if (i > 0) @(negedge vif.CLK);
                end
                
                @(posedge vif.CS_n); 
                #1; 
                // Release all data pins back to high-impedance pullup state
                vif.D3 <= 1'bz; 
                vif.D2 <= 1'bz; 
                vif.D1 <= 1'bz; 
                vif.D0 <= 1'bz; 
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master APB Control and Sequence Execution
        // ---------------------------------------------------------
        begin : master_apb_sequence
            
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            // Flush the FIFOs to remove ghost data left over from previous tests
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring QSPI Master Architecture ---");
            // Configure Clock Divider to 4 
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); 

            // Set Transfer Length to 0x1F (31) for 32 bits total
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); 

            $display("[INFO] --- STEP 2: Executing Direct Memory Access (DAC) Fetch ---");
            // FIX 1: Use pure Quad-DAC configuration! 
            // Enable DAC Memory Window (Bit 14 = 0x4000) + Quad Enable (Bit 10 = 0x0400) + Reset Release (Bit 2 = 0x0004). -> 0x4404.
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4404; agt.send_write(tx); 

            // FIX 2: Hardware synchronization delay to allow the AHB routing matrix to update!
            repeat(2) @(posedge vif.pclk);

            // Read directly from the DAC memory-mapped window (0x1000_0000).
            // The APB Agent will automatically wait for 'pready' while the DAC fetches the data.
            tx = new(); tx.paddr = 32'h1000_0000; 
            agt.send_read(tx);
            val = tx.prdata;
            
        end
    join_any
    
    // Safety cleanup: Terminate background threads and release all pins immediately to High-Z
    disable fork; 
    vif.D3 <= 1'bz; 
    vif.D2 <= 1'bz; 
    vif.D1 <= 1'bz; 
    vif.D0 <= 1'bz;

    // =================================================================
    // Result Evaluation & Data Integrity Verification
    // =================================================================
    $display("[INFO] --- STEP 3: Final Result Evaluation ---");
    if (val === 32'hA1B2_C3D4) begin
        $display("   [PASS] Read completed successfully via DAC pipeline. Data verified: %h\n", val);
    end else begin
        $display("   [FAIL] Data corruption detected on DAC fetch. Expected: 32'hA1B2_C3D4, Got: %h\n", val);
        test_pass = 1'b0;
    end

    // =================================================================
    // Global Scoreboard Registration
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-DAC-PPL-31");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-PPL-31");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
