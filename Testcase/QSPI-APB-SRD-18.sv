// =========================================================================
// TEST 18: Indirect Address Read (QSPI-APB-SRD-18)
// FIX: Replaced local mock slave with global flash model. Updated flash_delay
//      to 32 to wait out the indirect address TX phase before returning data.
//      Updated FSM busy bit polling to Bit 20.
// =========================================================================
task automatic run_test_18(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 18: Indirect Address Read (QSPI-APB-SRD-18)");
    $display("=======================================================================\n");

    // FIX: Use the global flash model
    tb_top.flash_enable = 1'b1;
    tb_top.flash_quad_mode = 1'b0;
    tb_top.flash.set_pattern(32'h1234_5678);
    // 32-bit TX phase for indirect address
    tb_top.flash.set_delay(32);

    begin : master_sequence
        $display("[INFO] --- STEP 0: Hardware Software Reset ---");
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
        repeat(5) @(posedge vif.pclk);

        $display("[INFO] --- STEP 1: Configuring Master ---");
        tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
        // XFERLEN = 31 (32 bits per phase)
        tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; tx.pstrb = 4'hF; agt.send_write(tx);

        $display("[INFO] --- STEP 2: Setting Indirect Read Address ---");
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
        // TX-then-RX Mode (Bits 14:13=10, Bit 0=1 -> 0x4001)
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; tx.pstrb = 4'hF; agt.send_write(tx);

        repeat(2) @(posedge vif.pclk);
        timeout_ctr = 0;
        do begin
            tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
            @(posedge vif.pclk);
            timeout_ctr++;
        // FIX: Poll Bit 20
        end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

        $display("[INFO] --- STEP 3: Reading Indirect Data ---");
        tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
        val = tx.prdata;
    end

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up.\n");
        test_pass = 1'b0;
    end else if (val === 32'h1234_5678) begin
        $display("   [PASS] Indirect read data: %h\n", val);
    end else begin
        $display("   [FAIL] Expected 12345678, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-SRD-18");
    tb_top.scoreboard.mark_as_run("QSPI-APB-SRD-18");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
