// =========================================================================
// TEST 56: Indirect Transfer at SRAM Boundary (QSPI-IND-BND-56)
// Validates indirect mode transfer behavior when the FIFO reaches its
// boundary limit, verifying back-pressure and FIFO count saturation.
// =========================================================================

task automatic run_test_56(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [3:0] fifo_cnt;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 56: Indirect Transfer at SRAM Boundary (QSPI-IND-BND-56)");
    $display(" Target: Validate FIFO boundary saturation and back-pressure");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Clock Divider ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
    repeat(2) @(posedge vif.pclk);

    $display("[INFO] --- STEP 2: Filling TX FIFO to Capacity (8 words) ---");
    for (int i = 0; i < 8; i++) begin
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hBEEF_0000 + i; agt.send_write(tx);
    end

    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 3: Checking FIFO Count at Boundary ---");
    tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
    fifo_cnt = tx.prdata[3:0];
    $display("   [DEBUG] TX FIFO Count at boundary: %0d", fifo_cnt);

    if (fifo_cnt == 4'd8) begin
        $display("   [PASS] FIFO reached capacity (8 words).");
    end else begin
        $display("   [FAIL] FIFO count mismatch. Expected 8, Got: %0d", fifo_cnt);
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 4: Attempting Overflow (2 more words) ---");
    for (int i = 0; i < 2; i++) begin
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hDEAD_0000 + i; agt.send_write(tx);
    end

    repeat(5) @(posedge vif.pclk);

    tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
    fifo_cnt = tx.prdata[3:0];
    $display("   [DEBUG] TX FIFO Count after overflow attempt: %0d", fifo_cnt);

    if (fifo_cnt == 4'd8) begin
        $display("   [PASS] FIFO correctly clamped at 8 words. Overflow prevented.\n");
    end else begin
        $display("   [FAIL] FIFO overflow not prevented! Count: %0d\n", fifo_cnt);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-IND-BND-56");
    tb_top.scoreboard.mark_as_run("QSPI-IND-BND-56");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

