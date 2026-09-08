// =========================================================================
// TEST 55: Chip Select Polarity / Decoder Disable (QSPI-APB-CFG-55)
// Validates CS_n polarity (active-low) and that CS_n de-asserts between
// transfers when not in back-to-back mode.
// =========================================================================

task automatic run_test_55(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    int cs_low_count = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 55: Chip Select Polarity / Decoder Disable (QSPI-APB-CFG-55)");
    $display(" Target: Validate CS_n active-low polarity and de-assertion");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Checking CS_n Idle State (Should be HIGH) ---");
    repeat(3) @(posedge vif.pclk);
    if (vif.CS_n === 1'b1) begin
        $display("   [PASS] CS_n is HIGH during idle (active-low confirmed).");
    end else begin
        $display("   [FAIL] CS_n is LOW during idle! Polarity incorrect.");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 2: Triggering Transfer and Monitoring CS_n ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hA5A5_A5A5; agt.send_write(tx);

    fork
        begin : cs_monitor
            forever begin
                @(negedge vif.CS_n);
                cs_low_count++;
            end
        end
        begin : master_seq
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);
        end
    join_any
    disable fork;

    $display("[INFO] --- STEP 3: Verifying CS_n Asserted During Transfer ---");
    if (cs_low_count > 0) begin
        $display("   [PASS] CS_n asserted LOW %0d time(s) during transfer.", cs_low_count);
    end else begin
        $display("   [FAIL] CS_n never asserted LOW during transfer!");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 4: Verifying CS_n Returns HIGH After Transfer ---");
    repeat(5) @(posedge vif.pclk);
    if (vif.CS_n === 1'b1) begin
        $display("   [PASS] CS_n returned to HIGH after transfer.\n");
    end else begin
        $display("   [FAIL] CS_n stuck LOW after transfer!\n");
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-CFG-55");
    tb_top.scoreboard.mark_as_run("QSPI-APB-CFG-55");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

