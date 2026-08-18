// =========================================================================
// TEST 14: Baud Rate Clock Divider (QSPI-PHY-REG-14)
// Comprehensive validation of SPI clock (sclk_out) generation, ensuring
// the clock divider mathematically scales the pclk correctly, followed by 
// robust FSM completion checks.
// =========================================================================

task automatic run_test_14(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;
    int pclk_count = 0;
    int measured_period = 0;

    $display("\n=======================================================================");
    $display(" TEST 14: Baud Rate Clock Divider");
    $display(" Target: QSPI-PHY-REG-14 | SPI Clock Generation and Scaling");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Clock Divider ---");
    // We set the divider to 4. 
    // According to the RTL: clk_div_cnt counts 0 to 4 (5 cycles) per SPI toggle.
    // Therefore, a full SPI clock period should be exactly 10 pclk cycles.
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); 
    
    // Set Transfer Length to 32 cycles to give us plenty of time to measure
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); 

    $display("[INFO] --- STEP 2: Triggering TX-Only Mode to Activate Clock ---");
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hFF00_FF00; agt.send_write(tx); 
    
    // Start TX-Only Mode (Bits 14:13=1, Bit 0=1) -> 0x2001
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx); 

    $display("[INFO] --- STEP 3: Mathematically Measuring Clock Period ---");
    fork
        begin : clk_measurement
            // Wait for the first rising edge to align
            @(posedge vif.CLK);
            
            // Count system clocks until the next rising edge
            fork
                begin
                    @(posedge vif.CLK);
                end
                begin
                    forever begin
                        @(posedge vif.pclk);
                        pclk_count++;
                    end
                end
            join_any
            disable fork; // Stop the pclk counter the instant the next SPI edge hits
            
            measured_period = pclk_count;
            $display("   [DEBUG] Measured SPI Clock Period: %0d pclk cycles", measured_period);
            
            if (measured_period == 10) begin
                $display("   [PASS] Clock divider mathematically verified! (Divider 4 = Period 10)");
            end else begin
                $display("   [FAIL] Clock divider scaling is incorrect!");
                test_pass = 1'b0;
            end
        end
        begin : timeout_guard
            repeat(400) @(posedge vif.pclk);
            $display("   [FAIL] Clock never toggled or timeout reached!\n");
            test_pass = 1'b0;
        end
    join_any
    disable fork; 

    $display("[INFO] --- STEP 4: Actively Polling FSM Status for Completion ---");
    // Proper CDC Delay & Polling Status Register (0x18) Bit 11
    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; 
        agt.send_read(tx);
        @(posedge vif.pclk); 
        timeout_ctr++;
    end while (tx.prdata[11] == 1'b1 && timeout_ctr < 2000);

    if (timeout_ctr >= 2000) begin
        $display("   [FAIL] FSM did not return to IDLE! Timeout reached while waiting for busy bit to clear.");
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] FSM returned to IDLE cleanly after %0d cycles.", timeout_ctr);
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-REG-14");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-REG-14");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
