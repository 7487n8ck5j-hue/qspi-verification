// =========================================================================
// TEST 05: QSPI Quad-SPI eXecute-In-Place (XIP) Boot Instruction Fetch
// Comprehensive diagnostic verification of high-speed Quad-SPI data 
// extraction, DAC memory mapping, dynamic XIP mode, and payload integrity.
// =========================================================================

task automatic run_test_05(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val; 
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 05: QSPI Quad-SPI XIP Boot Instruction Fetch");
    $display(" Target: QSPI-DAC-XIP-05 | Quad Mode Payload Extraction & Setup");
    $display("=======================================================================\n");

    // We use fork..join_any to run the APB Master and a Custom Quad-SPI Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Custom Quad-SPI Mock Slave
        // ---------------------------------------------------------
        begin : custom_quad_slave
            reg [31:0] payload = 32'h1A57_8C73;
            reg [3:0]  slave_drv;
            forever begin
                @(negedge vif.CS_n);
                
                // XIP mode drops the Instruction Phase, but STILL transmits the 24-bit Address Phase.
                // In Quad Mode (4 bits/clock), 24 bits takes exactly 6 clock cycles.
                repeat(6) @(negedge vif.CLK);
                #1; // Delta-cycle safety
                
                // Shift the first 4-bit nibble (MSB first)
                slave_drv = (payload >> (7*4)) & 4'hF; 
                vif.D3 <= slave_drv[3];
                vif.D2 <= slave_drv[2];
                vif.D1 <= slave_drv[1];
                vif.D0 <= slave_drv[0];

                // Shift the remaining 7 nibbles
                for (int i=6; i>=0; i--) begin 
                    @(negedge vif.CLK); 
                    #1; 
                    slave_drv = (payload >> (i*4)) & 4'hF; 
                    vif.D3 <= slave_drv[3];
                    vif.D2 <= slave_drv[2];
                    vif.D1 <= slave_drv[1];
                    vif.D0 <= slave_drv[0];
                end
                
                @(posedge vif.CS_n); 
                #1; 
                // Release the pins back to the default tb_top pullups
                vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz;
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master Polling Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            // Flush the FIFOs to remove ghost data left over from previous tests
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; 
            agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
            // Configure Clock Divider (0x0C)
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); 
            
            // Set Transfer Length to 32 bits (0x1F) for safe boundary alignment
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Configuring XIP Boot Mode ---");
            // FIX: We finally combine the correct XIP configuration WITH the pipeline delay!
            // DAC Enable (Bit 14 = 0x4000) + XIP Mode (Bit 13 = 0x2000) 
            // + Quad Enable (Bit 10 = 0x0400) + Reset Release (Bit 2 = 0x0004). -> 0x6404
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_6404; agt.send_write(tx);
            
            $display("[INFO] --- STEP 3: Executing Direct Memory Access (DAC) XIP Fetch ---");
            
            // FIX: Crucial hardware synchronization delay to allow the AHB routing matrix to update!
            repeat(2) @(posedge vif.pclk);
            
            // Read directly from the DAC memory-mapped boot window (0x1000_0000).
            tx = new(); tx.paddr = 32'h1000_0000; 
            agt.send_read(tx);
            val = tx.prdata;
            
        end
    join_any
    
    // Safety cleanup: Kill background slave and release pins immediately when sequence ends
    disable fork; 
    vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz;

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 4: Final Result Evaluation ---");
    if (val === 32'h1A57_8C73) begin
        $display("   [PASS] High-Speed Quad Boot Instruction Fetched Successfully via DAC: %h\n", val);
    end else begin
        $display("   [FAIL] Payload mismatch or corruption! Expected: 1A578C73, Got: %h\n", val);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-DAC-XIP-05");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-XIP-05");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
