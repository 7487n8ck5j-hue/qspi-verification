// =========================================================================
// TEST 41: System Interrupt Generation & Clearing (QSPI-APB-REG-41)
// Comprehensive verification of IRQ pin assertion, APB W1C
// (Write-1-to-Clear) mechanics, proper reset isolation, and CDC delays.
// =========================================================================

task automatic run_test_41(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 41: System Interrupt Generation & Clearing (QSPI-APB-REG-41)");
    $display(" Target: Validate IRQ assertion and W1C status register clearing");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    // FIX: Flush all leftover states (like TX_FULL from Test 39)
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring QSPI Master Architecture ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); 
    
    // FIX: Use Transfer Length register (0x10), NOT Dummy register (0x14)
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0004; agt.send_write(tx); 

    $display("[INFO] --- STEP 2: Triggering Transfer with Global Interrupts ENABLED ---");
    // Write data to TX register (0x04)
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hA5A5_5A5A; 
    agt.send_write(tx); 

    // FIX: Use TX-Only Mode + IntEn + Start (Bits 14:13=01, Bit 3=1, Bit 0=1 -> 0x2009)
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2009; 
    agt.send_write(tx); 

    $display("[INFO] --- STEP 3: Monitoring Hardware for IRQ Assertion ---");
    // Bounded loop looking for IRQ via virtual interface
    while (vif.irq == 1'b0 && timeout_ctr < 1000) begin
        @(posedge vif.pclk); 
        timeout_ctr++;
    end

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] Hardware failed to generate interrupt upon completion (Timeout).");
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] System Interrupt Generated! 'irq' pin HIGH.");
    end

    $display("[INFO] --- STEP 4: CPU Acknowledging (W1C to Interrupt Status) ---");
    // Keep IntEn (Bit 3), Write 1 to clear IntSts (Bit 4) -> 0x18
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0018; 
    agt.send_write(tx); 

    // Increase CDC propagation delay to ensure W1C fully resolves 
    // across the APB-to-SPI clock domain boundary before sampling.
    repeat(10) @(posedge vif.pclk); 
    
    // Read back the Status Register to verify internal state
    tx = new(); tx.paddr = 32'h00; 
    agt.send_read(tx);

    if (vif.irq === 1'b0 && tx.prdata[4] === 1'b0) begin
        $display("   [PASS] System Interrupt Cleared! 'irq' pin safely LOW and Status Bit 4 is 0.\n");
    end else begin
        $display("   [FAIL] Interrupt line stuck HIGH or Bit 4 uncleared after W1C operation. Readback: %h\n", tx.prdata);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-APB-REG-41");
    tb_top.scoreboard.mark_as_run("QSPI-APB-REG-41");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
