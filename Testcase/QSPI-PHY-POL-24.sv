// =========================================================================
// TEST 24: Clock Phase Configuration CPOL/CPHA (QSPI-PHY-POL-24)
// FIX: Explicitly clear Dummy Register (0x14) to prevent state leakage from
//      previous tests. Adjusted rx_delay to 8 to match the 8-bit TX phase.
// =========================================================================
task automatic run_test_24(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 24: Clock Phase Configuration CPOL/CPHA (QSPI-PHY-POL-24)");
    $display(" Target: Validate CPOL=1, CPHA=1 mode data capture");
    $display("=======================================================================\n");

    // Use global flash model
    tb_top.flash_enable = 1'b1;
    tb_top.flash_quad_mode = 1'b0;
    tb_top.flash.set_pattern(32'hF0F0_AAAA);
    // 8-bit TX phase before RX phase begins
    tb_top.flash.set_delay(8);

    begin : master_sequence
        $display("[INFO] --- STEP 0: Hardware Software Reset ---");
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
        repeat(5) @(posedge vif.pclk);

        $display("[INFO] --- STEP 1: Configuring CPOL=1, CPHA=1 ---");
        tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_000C; tx.pstrb = 4'hF; agt.send_write(tx);
        tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);
        // FIX: Clear Dummy cycles to 0 to wipe leaked state from Test 22!
        tx = new(); tx.paddr = 32'h14; tx.pwdata = 32'h0000_0000; tx.pstrb = 4'hF; agt.send_write(tx);

        $display("[INFO] --- STEP 2: Triggering Read ---");
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; tx.pstrb = 4'hF; agt.send_write(tx);

        repeat(2) @(posedge vif.pclk);
        timeout_ctr = 0;
        do begin
            tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
            @(posedge vif.pclk);
            timeout_ctr++;
        end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

        tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
        val = tx.prdata;
    end

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up with CPOL=1/CPHA=1.\n");
        test_pass = 1'b0;
    end else if (val[7:0] === 8'hF0) begin
        $display("   [PASS] CPOL=1/CPHA=1 data captured: %h\n", val);
    end else begin
        $display("   [FAIL] Expected F0, Got: %h\n", val[7:0]);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-PHY-POL-24");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-POL-24");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
