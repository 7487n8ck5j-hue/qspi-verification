// =========================================================================
// TEST 02: STIG Standard Transfer (QSPI-APB-REG-02)
// FIX: Force flash_enable to 1 to prevent cross-test contamination. Bound 
//      the rx_delay to exactly 8 to wait out the RDSR (0x05) command byte.
// =========================================================================
task automatic run_test_02(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 02: STIG Standard Transfer (QSPI-APB-REG-02)");
    $display(" Target: Validate WREN + RDSR command issuance via STIG");
    $display("=======================================================================\n");

    // FIX: Explicitly awaken the global flash model
    tb_top.flash_enable    = 1'b1;
    tb_top.flash_quad_mode = 1'b0;

    fork
        begin : master_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            // Set pattern to 0x0000_0000 to return WIP=0
            tb_top.flash.set_pattern(32'h0000_0000);

            $display("[INFO] --- STEP 1: Configuring Master ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Sending WREN (0x06) via TX FIFO ---");
            // TX ONLY mode, flash_delay doesn't matter since RX isn't active
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0600_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 3: Sending RDSR (0x05) via TX-then-RX ---");
            // Set delay to 8 to skip the 8-bit RDSR command phase
            tb_top.flash.set_delay(8);
            
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0500_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 4: Reading Status from RX FIFO ---");
            tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during STIG transfer.\n");
        test_pass = 1'b0;
    end else if (val[0] == 1'b0) begin
        $display("   [PASS] STIG transfer completed. RDSR returned WIP=0 (ready). Value: 0x%0h\n", val);
    end else begin
        $display("   [FAIL] RDSR still shows WIP=1. Value: 0x%0h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-REG-02");
    tb_top.scoreboard.mark_as_run("QSPI-APB-REG-02");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
