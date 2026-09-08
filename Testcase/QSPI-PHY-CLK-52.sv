// =========================================================================
// TEST 52: Clock Gating During Idle (QSPI-PHY-CLK-52)
// Validates that the SPI clock (CLK) is gated (held LOW) when the
// controller is idle, and only toggles during active transfers.
// =========================================================================

task automatic run_test_52(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    bit clk_idle_low;
    bit clk_active;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 52: Clock Gating During Idle (QSPI-PHY-CLK-52)");
    $display(" Target: Validate CLK gating when idle and toggling during transfer");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Checking CLK Idle State (Should be LOW) ---");
    repeat(5) @(posedge vif.pclk);
    clk_idle_low = (vif.CLK === 1'b0);
    if (clk_idle_low) begin
        $display("   [PASS] CLK correctly gated LOW during idle.");
    end else begin
        $display("   [FAIL] CLK is HIGH during idle! Clock not gated.");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 2: Triggering TX Transfer ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hAA55_AA55; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

    $display("[INFO] --- STEP 3: Checking CLK Toggles During Transfer ---");
    fork
        begin : clk_watcher
            @(posedge vif.CLK or negedge vif.CLK);
            clk_active = 1'b1;
        end
        begin : timeout_guard
            repeat(200) @(posedge vif.pclk);
            clk_active = 1'b0;
        end
    join_any
    disable fork;

    if (clk_active) begin
        $display("   [PASS] CLK toggled during active transfer.");
    end else begin
        $display("   [FAIL] CLK never toggled during transfer!");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 4: Waiting for FSM Idle ---");
    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
        @(posedge vif.pclk);
        timeout_ctr++;
    end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

    $display("[INFO] --- STEP 5: Checking CLK Returns to Idle ---");
    repeat(5) @(posedge vif.pclk);
    if (vif.CLK === 1'b0) begin
        $display("   [PASS] CLK returned to gated LOW after transfer.\n");
    end else begin
        $display("   [FAIL] CLK did not return to LOW after transfer!\n");
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-PHY-CLK-52");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-CLK-52");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

