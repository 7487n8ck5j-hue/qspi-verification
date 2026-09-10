// =========================================================================
// TEST 57: Out-of-Bounds Address Boundary (QSPI-DAC-BND-57)
// Validates that the AHB decoder actively blocks accesses above the 
// 24-bit (16MB) hardware addressing limit by asserting PSLVERR.
// =========================================================================

task automatic run_test_57(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 57: Out-of-Bounds Address Boundary (QSPI-DAC-BND-57)");
    $display(" Target: Validate AHB boundary decoder asserts PSLVERR on >16MB access");
    $display("=======================================================================\n");

    // No mock slave needed; the AHB decoder blocks the transaction before SPI starts.

    begin : master_ahb_sequence
        $display("[INFO] --- STEP 0: Hardware Software Reset ---");
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
        repeat(5) @(posedge vif.pclk);

        $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
        // Clock Divider
        tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);

        $display("[INFO] --- STEP 2: Enabling DAC Mode ---");
        // DAC Enable (0x4000) + Reset Release (0x0004) -> 0x4004
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4004; tx.pstrb = 4'hF; agt.send_write(tx);
        repeat(2) @(posedge vif.pclk);

        $display("[INFO] --- STEP 3: Executing Out-of-Bounds AHB Memory Fetch ---");
        // Access 0x1000_0000 (256MB offset) to intentionally trip the 16MB boundary
        tx = new(); tx.paddr = 32'h1000_0000; tx.pstrb = 4'hF;
        agt.send_read(tx);

        $display("[INFO] --- STEP 4: Final Result Evaluation ---");
        // The hardware must reject this with a slave error (pslverr == 1)
        if (tx.pslverr === 1'b1) begin
            $display("   [PASS] Boundary protection verified! AHB correctly rejected the out-of-bounds address with PSLVERR.\n");
        end else begin
            $display("   [FAIL] Boundary violation failed! Expected PSLVERR=1, Got pslverr: %b\n", tx.pslverr);
            test_pass = 1'b0;
        end
    end

    tb_top.scoreboard.set_current_test("QSPI-DAC-BND-57");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-BND-57");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
