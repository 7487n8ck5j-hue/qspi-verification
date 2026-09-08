// =========================================================================
// TEST 17: Data Learning Pattern (TDP) Training (QSPI-PHY-SDR-17)
// Comprehensive diagnostic verification of Data Learning Pattern training,
// RX-Only mode extraction, and strict CDC-aware APB polling.
// =========================================================================

task automatic run_test_17(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val; 
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 17: Data Learning Pattern (TDP) Training");
    $display(" Target: QSPI-PHY-SDR-17 | Training Pattern Extraction & Setup");
    $display("=======================================================================\n");

    // We use fork..join_any to run the APB Master and a Custom SPI Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Custom SPI Mock Slave (D1 / MISO Training Pattern)
        // ---------------------------------------------------------
        begin : custom_mock_slave
            reg [31:0] payload = 32'h5A5A_A5A5;
            forever begin
                @(negedge vif.CS_n);
                #1; // Delta-cycle safety
                
                // Shift out the 32-bit learning pattern bit by bit
                for (int i=31; i>=0; i--) begin 
                    vif.D1 <= payload[i]; 
                    if (i > 0) @(negedge vif.CLK); 
                end
                
                @(posedge vif.CS_n); 
                #1; vif.D1 <= 1'bz; // Drive High-Z
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master APB Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            // Flush the FIFOs to remove ghost data left over from previous tests
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; 
            agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring QSPI Master Architecture ---");
            // Clock Divider to 4
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
            // Set Transfer Length to 7 (8 clock cycles total) to read exactly 1 byte
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Triggering RX-Only Mode ---");
            // Trigger RX (Bits 14:13=00 [RX Mode], Bit 0=1 [Start] -> 0x0001)
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; agt.send_write(tx); 
            
            $display("[INFO] --- STEP 3: Actively Polling FSM Status ---");
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

            $display("[INFO] --- STEP 4: Extracting Payload from RX FIFO ---");
            // Read the captured training pattern byte from RX FIFO (0x08)
            tx = new(); tx.paddr = 32'h08; 
            agt.send_read(tx);
            val = tx.prdata;
        end
    join_any
    
    // Safety cleanup: Kill background slave and release pin immediately when sequence ends
    disable fork; 
    vif.D1 <= 1'bz; 

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] Hardware locked up during TDP training read.\n");
        test_pass = 1'b0;
    end else if (val === 32'h0000_005A) begin
        $display("   [PASS] Training Pattern correctly captured: %h\n", val);
    end else begin
        $display("   [FAIL] Clock phase slip detected! Expected 0000_005A, Got: %h\n", val);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-SDR-17");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-SDR-17");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
