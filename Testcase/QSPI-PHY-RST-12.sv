// =========================================================================
// TEST 12: Reset During Transfer Abort (QSPI-PHY-RST-12)
// FIX: Reprogrammed the Master's configuration registers in Step 5 because 
//      the hardware reset in Step 3 properly wiped them back to defaults.
// =========================================================================
task automatic run_test_12(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 12: Reset During Transfer Abort (QSPI-PHY-RST-12)");
    $display(" Target: Validate FSM returns to IDLE after mid-transfer reset");
    $display("=======================================================================\n");

    // Enable the global flash model
    tb_top.flash_enable = 1'b1;
    tb_top.flash_quad_mode = 1'b0;
    // Set response for the post-reset read 
    tb_top.flash.set_pattern(32'hCC00_0000);
    tb_top.flash.set_delay(0); // RX-ONLY transaction requires 0 delay

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);

    $display("[INFO] --- STEP 2: Starting SPI Transaction ---");
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx);

    // Wait a few cycles then assert reset mid-transfer
    repeat(3) @(posedge vif.pclk);

    $display("[INFO] --- STEP 3: Asserting Hardware Reset Mid-Transfer ---");
    vif.presetn = 1'b0;
    repeat(10) @(posedge vif.pclk);
    vif.presetn = 1'b1;
    $display("[INFO] --- STEP 4: Reset Released, Checking FSM Recovery ---");

    repeat(5) @(posedge vif.pclk);

    // Check Status Register — FSM should be IDLE (bit 20 = 0)
    tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
    val = tx.prdata;

    if (val[20] == 1'b0) begin
        $display("   [DEBUG] FSM is IDLE after reset. Status: %h", val);
    end else begin
        $display("   [DEBUG] FSM still BUSY after reset. Status: %h", val);
    end

    $display("[INFO] --- STEP 5: Reconfiguring Master & Attempting New Transaction ---");
    // FIX: Must reprogram configuration registers wiped by the hardware reset!
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);

    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx);

    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
        @(posedge vif.pclk);
        timeout_ctr++;
    end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

    tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
    val = tx.prdata;

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM did not recover after mid-transfer reset.\n");
        test_pass = 1'b0;
    end else if (val === 32'h0000_00CC) begin
        $display("   [PASS] FSM recovered after reset. Data: %h\n", val);
    end else begin
        $display("   [FAIL] Post-reset read mismatch. Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-PHY-RST-12");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-RST-12");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
