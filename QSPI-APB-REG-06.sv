// =========================================================================
// TEST 06: SPI Fast Read Instruction Verification (QSPI-APB-REG-06)
// Comprehensive validation of sequential TX/RX manual modes, Dummy Cycle 
// routing, and continuous clock-edge sampling via MISO (D1).
// =========================================================================

task automatic run_test_06(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 06: SPI Fast Read Instruction Verification");
    $display(" Target: QSPI-APB-REG-06 | Fast Read Sequence & Toggle Capture");
    $display("=======================================================================\n");

    // We use fork..join_any to run the APB Master and a Custom Toggling Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Custom Toggling Slave (D1 / MISO)
        // ---------------------------------------------------------
        begin : custom_toggling_slave
            reg slave_D1_val = 1'b1;
            forever begin
                // Wait for CS_n to go active
                @(negedge vif.CS_n);
                
                // Keep toggling on every negative clock edge as long as CS_n is low
                while (vif.CS_n == 1'b0) begin
                    @(negedge vif.CLK);
                    #1; // Delta-cycle safety
                    slave_D1_val = ~slave_D1_val;
                    vif.D1 <= slave_D1_val; 
                end
                
                // Release the pin back to the default pullups when CS_n goes high
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
            
            $display("[INFO] --- STEP 1: Configuring Clock Divider ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); 

            $display("[INFO] --- STEP 2: Transmit Fast Read Opcode (TX Phase) ---");
            // Pre-load TX FIFO
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0B00_0000; agt.send_write(tx); 
            
            // FIX: Use Transfer Length Register (0x10), NOT Dummy Register (0x14)
            // Set 7 for 8 clock cycles (1 byte opcode)
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; agt.send_write(tx); 
            
            // FIX: Start TX-Only Mode (Bit 13=1, Bit 0=1) -> 0x2001
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx); 
            
            // Wait for QSPI FSM to idle using proper CDC delay and Status Reg (0x18)
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; 
                agt.send_read(tx);
                @(posedge vif.pclk); 
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 3: Trigger RX to Capture Toggling Data ---");
            // Set Transfer Length Register to 31 for 32 clock cycles (4 bytes)
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); 
            
            // Start RX-Only Mode (Bits 14:13=0, Bit 0=1) -> 0x0001
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; agt.send_write(tx); 
            
            // Wait for QSPI FSM to idle using proper CDC delay and Status Reg (0x18)
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; 
                agt.send_read(tx);
                @(posedge vif.pclk); 
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);
            
            $display("[INFO] --- STEP 4: Extracting Payload from RX FIFO ---");
            // Read the captured payload from the RX FIFO (0x08)
            tx = new(); tx.paddr = 32'h08; 
            agt.send_read(tx);
            val = tx.prdata;
        end
    join_any
    
    // Safety cleanup: Kill background slave and release pins immediately when sequence ends
    disable fork; 
    vif.D1 <= 1'bz; 

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] Hardware locked up during Fast Read.");
        test_pass = 1'b0;
    end else if (val != 32'h0000_00FF && val != 32'h0000_0000) begin
        $display("   [PASS] Fast Read Data Captured Successfully: %h\n", val);
    end else begin
        $display("   [FAIL] Expected Valid Data, Got: %h\n", val); 
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-APB-REG-06");
    tb_top.scoreboard.mark_as_run("QSPI-APB-REG-06");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
