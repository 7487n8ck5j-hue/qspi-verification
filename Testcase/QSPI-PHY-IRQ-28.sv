// =========================================================================
// TEST 28: Hardware Interrupt Masking Configuration (QSPI-PHY-ERR-28)
// Comprehensive validation of interrupt gating, mask state verification, 
// physical pin tristate behavior, and internal status register synchronization.
// =========================================================================

task automatic run_test_28(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0; 
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 28: Hardware Interrupt Masking Configuration");
    $display(" Target: QSPI-PHY-ERR-28 | Masked Interrupt & FSM Status Verification");
    $display("=======================================================================\n");

    // Initialize interface signals to a safe known state prior to test execution
    vif.D1 <= 1'bz;

    // We use fork..join_any to run the APB Master and a Non-Blocking Mock Flash Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Non-Blocking Mock Flash Slave Architecture
        // ---------------------------------------------------------
        begin : non_blocking_mock_slave
            reg slave_oe_reg = 0;
            
             forever begin
                @(negedge vif.CS_n);
                slave_oe_reg = 1;
                
                while (vif.CS_n == 1'b0) begin
                    #1; // Delta-cycle propagation delay safety margin
                    if (slave_oe_reg) begin
                        vif.D1 <= 1'b1; // Safe procedural non-blocking driver update
                    end
                    @(posedge vif.CLK);
                end
                
                slave_oe_reg = 0;
                #1;
                vif.D1 <= 1'bz; // Return pin control to high-impedance state
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master APB Command Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            // FIX: Flush previous interrupts (like the Test 25 watchdog IRQ) to drop the pin to LOW
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Transfer Length ---");
            // FIX: Configure Transfer Length register (0x10), NOT Dummy (0x14)
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0004; agt.send_write(tx); 

            $display("[INFO] --- STEP 2: Initiating Transaction with Physical IRQ Masked ---");
            // Trigger QSPI controller start without interrupt generation enabled (Bit 3 = 0, Bit 0 = 1 -> 0x01)
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
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 10000);
        end
    join_any
    
    // Safety cleanup: Terminate background threads and ensure bus pins return immediately to High-Z
    disable fork; 
    vif.D1 <= 1'bz; 

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 4: Transaction Timeout Evaluation ---");
    if (timeout_ctr >= 10000) begin
        $display("   [FAIL] Hardware locked up during masked interrupt transfer. Bounded timeout reached (%0d cycles).", timeout_ctr);
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] Transaction completed successfully within bounded cycle limits (%0d cycles).", timeout_ctr);
    end

    // Allow clock domain synchronization across interface boundaries
    repeat(2) @(posedge vif.pclk);

    $display("[INFO] --- STEP 5: Validating Physical Interrupt Pin State ---");
    // Validate that the pin stayed LOW because we didn't enable interrupts globally
    if (vif.irq === 1'b1) begin
        $display("   [FAIL] Architectural Violation: Physical 'irq' pin went high despite IntEn mask being cleared.");
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] Physical 'irq' pin correctly remained low, confirming proper interrupt masking.");
    end

    $display("[INFO] --- STEP 6: Validating Internal Completion Register Status ---");
    // Validate that the internal logic still flagged completion in the Control/Status mapping
    tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
    
    if (tx.prdata[4] === 1'b1) begin
        $display("   [PASS] Internal completion status bit (Bit 4) logged properly in register.");
    end else begin
        $display("   [FAIL] Status register error: Controller did not set internal completion bit. Read data: %h", tx.prdata);
        test_pass = 1'b0;
    end
    $display("\n");

    // =================================================================
    // Global Scoreboard Registration & Results Harmonization
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-IRQ-28");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-IRQ-28");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
