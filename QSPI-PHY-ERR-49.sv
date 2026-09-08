// =========================================================================
// TEST 49: Illegal Opcode / Unsupported Command (QSPI-PHY-ERR-49)
// Comprehensive validation of error handling when an illegal/unsupported
// SPI command opcode is sent to the flash device.
// =========================================================================

task automatic run_test_49(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 49: Illegal Opcode / Unsupported Command (QSPI-PHY-ERR-49)");
    $display(" Target: Validate error handling for unsupported SPI commands");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; agt.send_write(tx);

    $display("[INFO] --- STEP 2: Sending Illegal Opcode (0xFF) ---");
    // 0xFF is not a valid SPI flash command
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hFF00_0000; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

    $display("[INFO] --- STEP 3: Polling FSM Status ---");
    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
        @(posedge vif.pclk);
        timeout_ctr++;
    end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

    $display("[INFO] --- STEP 4: Sending Another Illegal Opcode (0x00) ---");
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0000_0000; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
        @(posedge vif.pclk);
        timeout_ctr++;
    end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up after illegal opcode. Controller did not recover.\n");
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] Controller safely handled illegal opcode. FSM returned to IDLE.\n");
    end

    tb_top.scoreboard.set_current_test("QSPI-PHY-ERR-49");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-ERR-49");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

