// =========================================================================
// TEST 23: SRAM Partition Configuration (QSPI-APB-PAR-23)
// Comprehensive validation of internal SRAM memory division, DMA threshold 
// configurations, test isolation, and proper APB readback verification.
// =========================================================================

task automatic run_test_23(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 23: SRAM Partition Configuration (QSPI-APB-PAR-23)");
    $display(" Target: Validate internal SRAM memory division & DMA bounds");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    // Flush the FIFOs to ensure memory banks are truly empty for baseline testing
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring SRAM Partition Thresholds ---");
    // RX Threshold = 4 (Bits 23:16), TX Threshold = 4 (Bits 15:8), Enable Both (Bits 1:0) -> 0x0004_0403
    tx = new(); tx.paddr = 32'h28; tx.pwdata = 32'h0004_0403; 
    agt.send_write(tx); 

    $display("[INFO] --- STEP 2: Verifying Configuration Readback ---");
    // Diagnostic readback to prove the RTL latched the thresholds correctly
    tx = new(); tx.paddr = 32'h28; agt.send_read(tx);
    $display("   [DEBUG] DMA_CTRL (0x28) Readback: %h", tx.prdata);
    
    if (tx.prdata === 32'h0004_0403) begin
        $display("   [PASS] DMA threshold configuration correctly stored in APB registers.");
    end else begin
        $display("   [FAIL] DMA threshold configuration mismatch! Expected 0004_0403, Got: %h", tx.prdata);
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 3: Verifying TX Boundary Logic Response ---");
    repeat(2) @(posedge vif.pclk); // Wait for signals to propagate

    $display("   [DEBUG] Physical TX_DMA_REQ Pin: %b", vif.tx_dma_req);
    if (vif.tx_dma_req === 1'b1) begin
        $display("   [PASS] TX Memory partition evaluated correctly (Empty queue asserted data request).");
    end else begin
        $display("   [FAIL] TX Memory partition evaluation failed (Pin did not assert).");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 4: Verifying RX Boundary Logic Response ---");
    $display("   [DEBUG] Physical RX_DMA_REQ Pin: %b", vif.rx_dma_req);
    if (vif.rx_dma_req === 1'b0) begin
        $display("   [PASS] RX Memory partition evaluated correctly (Empty queue blocked read request).\n");
    end else begin
        $display("   [FAIL] RX Memory partition evaluation failed (Pin erroneously asserted).\n");
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-APB-PAR-23");
    tb_top.scoreboard.mark_as_run("QSPI-APB-PAR-23");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
