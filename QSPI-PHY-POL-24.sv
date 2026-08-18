// =========================================================================
// TEST 24: Custom Hardware Status Polling (QSPI-PHY-POL-24)
// Comprehensive diagnostic verification of continuous status polling, 
// utilizing TX-then-RX mode, strict CDC delays, and APB isolation.
// =========================================================================

task automatic run_test_24(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val = 32'h0000_0080;
    int poll_ctr = 0;
    int apb_timeout = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 24: Custom Hardware Status Polling");
    $display(" Target: QSPI-PHY-POL-24 | Validate continuous looping for device status");
    $display("=======================================================================\n");

    // We use fork..join_any to run the APB Master and a Custom Polling Flash Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Custom Polling Status Mock Slave
        // ---------------------------------------------------------
        begin : custom_polling_slave
            int slave_poll_count = 0;
            reg slave_D1_val = 1'b1;
            forever begin
                @(negedge vif.CS_n);
                
                // Skip the command phase (8 clock cycles for the 0x70 Opcode)
                for (int i=0; i<8; i++) @(negedge vif.CLK);
                
                // Force D1 output enabled (Bit 7: 1 for first 2 polls, then 0 for Idle)
                #1; vif.D1 <= (slave_poll_count < 2) ? 1'b1 : 1'b0;
                
                // Shift out the remaining 7 bits for the status byte
                for (int i=6; i>=0; i--) begin
                    @(negedge vif.CLK);
                    #1;
                    vif.D1 <= 1'b0; 
                end
                
                slave_poll_count++;
                @(posedge vif.CS_n);
                #1;
                vif.D1 <= 1'bz; // Drive High-Z
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master Polling Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
            // FIX: Transfer Length to 15 (16 cycles: 8 for TX Opcode + 8 for RX Status)
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_000F; agt.send_write(tx); 

            $display("[INFO] --- STEP 2: Executing Status Polling Loop ---");
            while (val[7] == 1'b1 && poll_ctr < 50) begin
                $display("   [DEBUG] Polling Iteration: %0d", poll_ctr + 1);
                
                // Write Opcode (0x70 = Read Status Register) to TX FIFO
                tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h7000_0000; agt.send_write(tx); 
                
                // FIX: Trigger TX-then-RX Mode (Bits 14:13=10 [TX/RX], Bit 0=1 [Start]) -> 0x4001
                tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; agt.send_write(tx); 
                
                // FIX: Proper CDC Delay & Polling Status Register (0x18) Bit 11
                repeat(2) @(posedge vif.pclk);
                apb_timeout = 0;
                do begin
                    tx = new(); tx.paddr = 32'h18; 
                    agt.send_read(tx);
                    @(posedge vif.pclk); 
                    apb_timeout++;
                end while (tx.prdata[11] == 1'b1 && apb_timeout < 1000);
                
                if (apb_timeout >= 1000) begin
                    $display("   [FAIL] APB internal state machine timed out during poll!");
                    test_pass = 1'b0;
                    break;
                end

                // Read Status from RX FIFO (0x08)
                tx = new(); tx.paddr = 32'h08; 
                agt.send_read(tx);
                val = tx.prdata;
                
                if (val[7] == 1'b1) begin
                    $display("   [DEBUG] Status Register Bit 7 is HIGH (Busy). Re-issuing query...");
                end else begin
                    $display("   [PASS] Target hardware resolved block (Bit 7 LOW). Polling concluded properly.");
                end
                
                poll_ctr++;
            end
        end
    join_any
    
    // Safety cleanup: Kill background slave and release pins immediately
    disable fork; 
    vif.D1 <= 1'bz; 

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 3: Final Result Evaluation ---");
    if (poll_ctr >= 50) begin
        $display("   [FAIL] Hardware locked up. Polling limit (50) exceeded.");
        test_pass = 1'b0;
    end else if (apb_timeout >= 1000) begin
        $display("   [FAIL] Sequence aborted due to APB timeout.");
    end else begin
        $display("   [PASS] Custom hardware status polling validated across %0d iterations.\n", poll_ctr);
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-POL-24");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-POL-24");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
