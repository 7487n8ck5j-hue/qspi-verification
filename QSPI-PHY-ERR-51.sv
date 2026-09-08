// =========================================================================
// TEST 51: DLL Lock Failure / Timeout Handling (QSPI-PHY-ERR-51)
// Validates that the controller handles DLL lock failure gracefully
// via timeout watchdog and status flag assertion.
// =========================================================================

task automatic run_test_51(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 51: DLL Lock Failure / Timeout Handling (QSPI-PHY-ERR-51)");
    $display(" Target: Validate timeout watchdog and FSM abort on lock failure");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Strict Timeout Limit ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_1000; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h24; tx.pwdata = 32'h8000_0010; agt.send_write(tx);

    $display("[INFO] --- STEP 2: Triggering Transfer with Interrupts Enabled ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0809; agt.send_write(tx);

    $display("[INFO] --- STEP 3: Monitoring IRQ Pin ---");
    timeout_ctr = 0;
    while (vif.irq == 1'b0 && timeout_ctr < 2000) begin
        @(posedge vif.pclk);
        timeout_ctr++;
    end

    if (timeout_ctr >= 2000) begin
        $display("   [FAIL] IRQ never asserted within 2000 cycles.");
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] IRQ asserted after %0d cycles.", timeout_ctr);
    end

    $display("[INFO] --- STEP 4: Checking Timeout Status Flag ---");
    tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
    if (tx.prdata[4] == 1'b1) begin
        $display("   [PASS] Timeout flag (Bit 4) asserted.\n");
    end else begin
        $display("   [FAIL] Timeout flag (Bit 4) not set! Status: 0x%0h\n", tx.prdata);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-PHY-ERR-51");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-ERR-51");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

