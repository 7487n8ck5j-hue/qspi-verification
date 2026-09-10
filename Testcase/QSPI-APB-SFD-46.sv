// =========================================================================
// TEST 46: SFDP Parameter Table Read (QSPI-APB-SFD-46)
// FIX: Utilizes global flash model with set_delay(40) to skip command, 
//      address, and dummy cycles before shifting out the SFDP signature.
// =========================================================================

task automatic run_test_46(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 46: SFDP Parameter Table Read (QSPI-APB-SFD-46)");
    $display(" Target: Validate SFDP (0x5A) command and parameter table capture");
    $display("=======================================================================\n");

    tb_top.flash_enable    = 1'b1;
    tb_top.flash_quad_mode = 1'b0;
    tb_top.flash.set_pattern(32'h4650_4453); // "SFDS"
    tb_top.flash.set_delay(40);             // 8-bit cmd + 24-bit addr + 8 dummy cycles

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
    // Transfer Length = 31 (32 cycles = 4 bytes of SFDP data)
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx);

    $display("[INFO] --- STEP 2: Sending SFDP Command (0x5A) via TX ---");
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h5A00_0000; agt.send_write(tx);
    
    // Set Dummy cycles to 8
    tx = new(); tx.paddr = 32'h14; tx.pwdata = 32'h0000_0008; agt.send_write(tx);

    // TX + DUMMY + RX Mode (0x6001)
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_6001; agt.send_write(tx);

    $display("[INFO] --- STEP 3: Polling FSM Status ---");
    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
        @(posedge vif.pclk);
        timeout_ctr++;
    end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

    $display("[INFO] --- STEP 4: Extracting SFDP Signature from RX FIFO ---");
    tx = new(); tx.paddr = 32'h08; agt.send_read(tx);
    val = tx.prdata;

    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during SFDP read.\n");
        test_pass = 1'b0;
    end else if (val === 32'h46504453) begin
        $display("   [PASS] SFDP signature verified: 0x%0h\n", val);
    end else begin
        $display("   [FAIL] SFDP signature mismatch. Expected 46504453, Got: 0x%0h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-SFD-46");
    tb_top.scoreboard.mark_as_run("QSPI-APB-SFD-46");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
