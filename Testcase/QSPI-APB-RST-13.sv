// =========================================================================
// TEST 13: APB Register POR Default Validation (QSPI-APB-RST-13)
// Comprehensive validation of Power-On Reset (POR) register states, 
// updated to reflect the Test 02 RTL bug fix for FLASH_RST_n.
// =========================================================================

task automatic run_test_13(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 13: APB Register POR Default Validation");
    $display(" Target: Validate Power-On Reset (POR) register states.");
    $display("=======================================================================\n");
    
    $display("[INFO] --- STEP 1: Engaging System Reset ---");
    vif.presetn = 1'b0;
    repeat(5) @(posedge vif.pclk); // Hold reset low for 5 clock cycles
    vif.presetn = 1'b1;
    repeat(5) @(posedge vif.pclk); // Allow system to stabilize

    $display("[INFO] --- STEP 2: Checking Architectural Defaults via APB ---");
    
    // ---------------------------------------------------------
    // Check CTRL_REG (0x00)
    // ---------------------------------------------------------
    tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
    if (tx.prdata === 32'h0000_0004) begin
        $display("   [PASS] CTRL_REG     (0x00) POR is 0x0000_0004 (FLASH_RST_n is HIGH)");
    end else begin 
        $display("   [FAIL] CTRL_REG     (0x00) POR Mismatch! Expected: 00000004, Got: %h", tx.prdata);
        test_pass = 1'b0;
    end

    // ---------------------------------------------------------
    // Check CLKDIV_REG (0x0C) - ADDED FOR COVERAGE
    // ---------------------------------------------------------
    tx = new(); tx.paddr = 32'h0C; agt.send_read(tx);
    if (tx.prdata === 32'h0000_0001) begin
        $display("   [PASS] CLKDIV_REG   (0x0C) POR is 0x0000_0001");
    end else begin 
        $display("   [FAIL] CLKDIV_REG   (0x0C) POR Mismatch! Expected: 00000001, Got: %h", tx.prdata);
        test_pass = 1'b0;
    end

    // ---------------------------------------------------------
    // Check XFERLEN_REG (0x10) - ADDED FOR COVERAGE
    // ---------------------------------------------------------
    tx = new(); tx.paddr = 32'h10; agt.send_read(tx);
    if (tx.prdata === 32'h0000_001F) begin
        $display("   [PASS] XFERLEN_REG  (0x10) POR is 0x0000_001F");
    end else begin 
        $display("   [FAIL] XFERLEN_REG  (0x10) POR Mismatch! Expected: 0000001f, Got: %h", tx.prdata);
        test_pass = 1'b0;
    end

    // ---------------------------------------------------------
    // Check DUMMY_CTRL (0x14)
    // ---------------------------------------------------------
    tx = new(); tx.paddr = 32'h14; agt.send_read(tx);
    if (tx.prdata === 32'h0000_0000) begin
        $display("   [PASS] DUMMY_CTRL   (0x14) POR is 0x0000_0000");
    end else begin 
        $display("   [FAIL] DUMMY_CTRL   (0x14) POR Mismatch! Expected: 00000000, Got: %h", tx.prdata);
        test_pass = 1'b0;
    end

    // ---------------------------------------------------------
    // Check TIMEOUT_CTRL (0x24)
    // ---------------------------------------------------------
    tx = new(); tx.paddr = 32'h24; agt.send_read(tx);
    if (tx.prdata === 32'h0000_0000) begin
        $display("   [PASS] TIMEOUT_CTRL (0x24) POR is 0x0000_0000");
    end else begin 
        $display("   [FAIL] TIMEOUT_CTRL (0x24) POR Mismatch! Expected: 00000000, Got: %h", tx.prdata);
        test_pass = 1'b0;
    end

    // ---------------------------------------------------------
    // Check DMA_CTRL (0x28)
    // ---------------------------------------------------------
    tx = new(); tx.paddr = 32'h28; agt.send_read(tx);
    if (tx.prdata === 32'h0000_0000) begin
        $display("   [PASS] DMA_CTRL     (0x28) POR is 0x0000_0000\n");
    end else begin 
        $display("   [FAIL] DMA_CTRL     (0x28) POR Mismatch! Expected: 00000000, Got: %h\n", tx.prdata);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-APB-RST-13");
    tb_top.scoreboard.mark_as_run("QSPI-APB-RST-13");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
