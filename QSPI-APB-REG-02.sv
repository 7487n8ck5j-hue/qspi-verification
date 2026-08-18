// =========================================================================
// TEST 02: Hardware Flash Reset Pin Validation (QSPI-APB-REG-02)
// Comprehensive diagnostic sequence to validate internal register mapping
// against the physical FLASH_RST_n output pin safe-boot behavior.
// =========================================================================

task automatic run_test_02(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 02: Hardware Flash Reset Pin Validation (QSPI-APB-REG-02)");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Ensuring Test Isolation via Software Reset ---");
    // FIX: We cannot rely on tb_top's physical presetn if tests run sequentially!
    // Issue a Software Reset to clear leftover garbage from previous tests.
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Boot-Up Default State Check (Expected: LOW) ---");
    // Read the internal Control Register (0x00) to see what the RTL *thinks* the state is
    tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
    $display("   [DEBUG] APB Read Control Reg (0x00) : %h", tx.prdata);
    $display("   [DEBUG] Physical FLASH_RST_n Pin    : %b", vif.FLASH_RST_n);

    // The physical pin should be LOW (0) by default to hold flash safely in reset
    if (vif.FLASH_RST_n === 1'b0 && tx.prdata[2] === 1'b0) begin
        $display("   [PASS] 1. Default state safely holds external device in reset (LOW).\n");
    end else begin 
        test_pass = 1'b0;
        $display("   [FAIL] 1. Default state mismatch! Pin = %b, Control Reg[2] = %b\n", vif.FLASH_RST_n, tx.prdata[2]);
    end

    // Check 2: Write 0x04 to Control Register (0x00) to release Bit 2 (Rst_n) HIGH
    if (test_pass) begin
        $display("[INFO] --- STEP 2: Releasing Reset HIGH via APB ---");
        tx = new();
        tx.paddr  = 32'h00;
        tx.pwdata = 32'h0000_0004;
        agt.send_write(tx); 
        
        // Wait for the APB transaction to complete and the physical pin to update
        repeat(5) @(posedge vif.pclk);
        
        // Read back the internal register for visibility
        tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
        $display("   [DEBUG] APB Read Control Reg (0x00) : %h", tx.prdata);
        $display("   [DEBUG] Physical FLASH_RST_n Pin    : %b", vif.FLASH_RST_n);

        if (vif.FLASH_RST_n === 1'b1 && tx.prdata[2] === 1'b1) begin
            $display("   [PASS] 2. Reset successfully released HIGH.\n");
        end else begin 
            $display("   [FAIL] 2. Failed to release HIGH! (Pin value = %b)\n", vif.FLASH_RST_n); 
            test_pass = 1'b0;
        end
    end

    // Check 3: Write 0x00 to Control Register (0x00) to pull Bit 2 (Rst_n) LOW
    if (test_pass) begin
        $display("[INFO] --- STEP 3: Pulling Reset LOW via APB ---");
        tx = new();
        tx.paddr  = 32'h00;
        tx.pwdata = 32'h0000_0000;
        agt.send_write(tx); 
        
        repeat(5) @(posedge vif.pclk);

        // Read back the internal register for visibility
        tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
        $display("   [DEBUG] APB Read Control Reg (0x00) : %h", tx.prdata);
        $display("   [DEBUG] Physical FLASH_RST_n Pin    : %b", vif.FLASH_RST_n);

        // Final verification
        if (vif.FLASH_RST_n === 1'b0 && tx.prdata[2] === 1'b0) begin
            $display("   [PASS] TEST 02 PASSED! Pin tracking behavior verified.\n");
        end else begin
            $display("   [FAIL] 3. Failed to pull LOW! (Pin value = %b)\n", vif.FLASH_RST_n);
            test_pass = 1'b0;
        end
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-APB-REG-02");
    tb_top.scoreboard.mark_as_run("QSPI-APB-REG-02");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
