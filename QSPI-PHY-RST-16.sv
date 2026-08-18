// =========================================================================
// TEST 16: Hardware Reset Pin Routing (QSPI-PHY-RST-16)
// Comprehensive verification of dedicated target reset routing, APB register 
// default state retention, and independent safe-boot isolation.
// =========================================================================

task automatic run_test_16(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    bit test_pass = 1'b1; // Accumulator for multi-stage test

    $display("\n=======================================================================");
    $display(" TEST 16: Hardware Reset Pin Routing");
    $display(" Target: QSPI-PHY-RST-16 | Dedicated Target Reset Validation");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Ensuring Test Isolation via Software Reset ---");
    // Flush out any residual states to simulate a fresh boot environment
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Checking Default Pin State (Expected: LOW) ---");
    repeat(2) @(posedge vif.pclk);
    
    // Diagnostic Readback of Control Register
    tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
    $display("   [DEBUG] Control Reg (0x00) Default State : %h", tx.prdata);
    $display("   [DEBUG] Physical FLASH_RST_n Pin         : %b", vif.FLASH_RST_n);

    // FIX: A proper reset state clears the register to 0, holding the external pin LOW for safety.
    if (vif.FLASH_RST_n === 1'b0 && tx.prdata[2] === 1'b0) begin
        $display("   [PASS] Default reset state correctly holds external device in reset (LOW).");
    end else begin 
        $display("   [FAIL] Default reset state mismatch! Pin = %b, Control Reg[2] = %b", vif.FLASH_RST_n, tx.prdata[2]);
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 2: Releasing Physical Hardware Reset (Raise HIGH) ---");
    // Set Bit 2 to release FLASH_RST_n to HIGH -> 0x0000_0004
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0004; 
    agt.send_write(tx); 
    
    repeat(3) @(posedge vif.pclk);
    
    // Diagnostic Readback
    tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
    $display("   [DEBUG] Control Reg (0x00) Readback      : %h", tx.prdata);
    $display("   [DEBUG] Physical FLASH_RST_n Pin         : %b", vif.FLASH_RST_n);

    if (vif.FLASH_RST_n === 1'b1 && tx.prdata[2] === 1'b1) begin
        $display("   [PASS] FLASH_RST_n successfully released to HIGH via APB command.");
    end else begin 
        $display("   [FAIL] FLASH_RST_n failed to release! Pin = %b, Control Reg[2] = %b", vif.FLASH_RST_n, tx.prdata[2]);
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 3: Activating Physical Hardware Reset (Drop LOW) ---");
    // Clear Bit 2 to pull FLASH_RST_n back LOW -> 0x0000_0000
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0000; 
    agt.send_write(tx); 
    
    repeat(3) @(posedge vif.pclk);

    // Diagnostic Readback
    tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
    $display("   [DEBUG] Control Reg (0x00) Readback      : %h", tx.prdata);
    $display("   [DEBUG] Physical FLASH_RST_n Pin         : %b", vif.FLASH_RST_n);

    if (vif.FLASH_RST_n === 1'b0 && tx.prdata[2] === 1'b0) begin
        $display("   [PASS] FLASH_RST_n safely pulled LOW to manually reset external device.\n");
    end else begin 
        $display("   [FAIL] FLASH_RST_n failed to drop! Pin = %b, Control Reg[2] = %b\n", vif.FLASH_RST_n, tx.prdata[2]);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-RST-16");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-RST-16");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
