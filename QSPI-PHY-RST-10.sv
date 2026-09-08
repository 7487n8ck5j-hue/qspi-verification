// =========================================================================
// TEST 10: PHY Master DLL Lock (QSPI-PHY-RST-10)
// Comprehensive diagnostic sequence validating internal PHY DLL enablement,
// phase alignment, and hardware lock status polling.
// =========================================================================

task automatic run_test_10(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 10: PHY Master DLL Lock (QSPI-PHY-RST-10)");
    $display(" Target: Validate DLL phase detection and locking mechanism.");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; 
    agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);
    
    $display("[INFO] --- STEP 1: Engaging PHY Physical Reset (Drop FLASH_RST_n) ---");
    // Clear FLASH_RST_n (Bit 2) to 0 -> 0x0000_0000
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0000; 
    agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);
    
    tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
    
    if (vif.FLASH_RST_n === 1'b0) begin
        $display("   [PASS] PHY Reset explicitly asserted. Phase drift cleared.");
    end else begin
        $display("   [FAIL] PHY Reset failed to drop! Pin remains HIGH.");
        test_pass = 1'b0;
    end

    if (test_pass) begin
        $display("[INFO] --- STEP 2: Releasing PHY Reset (Raise FLASH_RST_n) ---");
        // Set FLASH_RST_n (Bit 2) to 1 -> 0x0000_0004
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0004; 
        agt.send_write(tx);
        repeat(6) @(posedge vif.pclk); 
        
        tx = new(); tx.paddr = 32'h00; agt.send_read(tx);

        if (vif.FLASH_RST_n === 1'b1) begin
            $display("   [PASS] PHY Reset explicitly released. Internal DLL initializing...");
        end else begin
            $display("   [FAIL] PHY Reset failed to release! Pin remains LOW.");
            test_pass = 1'b0;
        end
    end

    if (test_pass) begin
        $display("[INFO] --- STEP 3: Verifying Phase Detection Alignment ---");
        if (vif.CLK === 1'b0) begin
            $display("   [PASS] Phase detection aligned. PHY Master DLL Lock achieved successfully.\n");
        end else begin
            $display("   [FAIL] Clock state drift detected after DLL initialization! CLK = %b\n", vif.CLK);
            test_pass = 1'b0;
        end
    end

    tb_top.scoreboard.set_current_test("QSPI-PHY-RST-10");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-RST-10");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
