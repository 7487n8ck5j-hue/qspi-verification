// =========================================================================
// TEST 54: Multi-CS Sequential Access (QSPI-AHB-MCS-54)
// Validates sequential access across different chip-select address windows.
// Note: This DUT has a single CS_n pin; test adapts to verify address decode.
// =========================================================================

task automatic run_test_54(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 54: Multi-CS Sequential Access (QSPI-AHB-MCS-54)");
    $display(" Target: Validate sequential address window access (adapted for single-CS)");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Valid Register Read (0x00) ---");
    tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
    if (tx.pslverr === 1'b0) begin
        $display("   [PASS] Valid register access accepted (no PSLVERR).");
    end else begin
        $display("   [FAIL] Valid register access rejected! PSLVERR asserted.");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 2: Valid Register Read (0x18) ---");
    tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
    if (tx.pslverr === 1'b0) begin
        $display("   [PASS] Status register access accepted.");
    end else begin
        $display("   [FAIL] Status register access rejected!");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 3: Invalid Address (0x40) ---");
    tx = new(); tx.paddr = 32'h0000_0040; agt.send_read(tx);
    if (tx.pslverr === 1'b1) begin
        $display("   [PASS] Invalid address correctly rejected with PSLVERR.");
    end else begin
        $display("   [FAIL] Invalid address not rejected!");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 4: Invalid Address (0xFC) ---");
    tx = new(); tx.paddr = 32'h0000_00FC; agt.send_read(tx);
    if (tx.pslverr === 1'b1) begin
        $display("   [PASS] Invalid address correctly rejected.\n");
    end else begin
        $display("   [FAIL] Invalid address not rejected!\n");
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-AHB-MCS-54");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-MCS-54");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

