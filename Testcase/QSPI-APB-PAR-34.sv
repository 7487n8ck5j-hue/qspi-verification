// =========================================================================
// TEST 34: SRAM Partition Allocation (QSPI-APB-PAR-34)
// Comprehensive verification of shared memory partition thresholds, indirect 
// access allocation boundaries, hardware back-pressure, and APB readbacks.
// =========================================================================

task automatic run_test_34(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 34: SRAM Partition Allocation");
    $display(" Target: QSPI-APB-PAR-34 | Shared Memory Management & Partition Limits");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    // Flush previous states to ensure FIFO is empty and DMA pins reset
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; 
    agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Constraining SRAM allocation blocks (TX Limit = 2) ---");
    // Write to DMA Control Register (0x28)
    tx = new(); tx.paddr = 32'h28; tx.pwdata = 32'h0000_0201; 
    agt.send_write(tx); 
    
    // Diagnostic Readback
    tx = new(); tx.paddr = 32'h28; agt.send_read(tx);
    if (tx.prdata === 32'h0000_0201) begin
        $display("   [PASS] DMA threshold configuration correctly latched in APB registers.");
    end else begin
        $display("   [FAIL] DMA threshold mismatch! Expected: 00000201, Got: %h", tx.prdata);
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 2: Verifying Initial DMA Request State ---");
    repeat(2) @(posedge vif.pclk);
    if (vif.tx_dma_req === 1'b1) begin
        $display("   [PASS] TX DMA Request active when FIFO is empty (Count 0 <= Threshold 2).");
    end else begin
        $display("   [FAIL] TX DMA Request inactive when FIFO is empty!");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 3: Attempting to overload allocated INDAC partition ---");
    // Push 4 words into the constrained block (exceeding the threshold of 2)
    for (int i = 0; i < 4; i++) begin
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hF0F0_0F0F; 
        agt.send_write(tx); 
    end

    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 4: Evaluating Hardware Back-Pressure Response ---");
    // Verify physical pin
    if (vif.tx_dma_req === 1'b0) begin
        $display("   [PASS] Shared memory allocation obeyed. DMA queue request muted above partition limits.");
    end else begin
        $display("   [FAIL] Partition allocation ignored by hardware. DMA request active unexpectedly.");
        test_pass = 1'b0;
    end

    // Verify internal FIFO state via Status Register (0x18)
    tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
    $display("   [DEBUG] Final Status Register (0x18) TX_FIFO_CNT: %0d", tx.prdata[3:0]);
    
    if (tx.prdata[3:0] == 4'd4) begin
        $display("   [PASS] Internal memory accepted exactly 4 words, confirming boundary saturation.\n");
    end else begin
        $display("   [FAIL] Expected 4 words in TX FIFO, but read: %0d\n", tx.prdata[3:0]);
        test_pass = 1'b0;
    end

    // =================================================================
    // Global Scoreboard Registration
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-APB-PAR-34");
    tb_top.scoreboard.mark_as_run("QSPI-APB-PAR-34");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
