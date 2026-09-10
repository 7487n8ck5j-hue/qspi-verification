// =========================================================================
// TEST 48: Software Write Protection (BP bits) (QSPI-AHB-WPR-48)
// FIX: Updated evaluation to check val[7:0] for the 8-bit right-aligned 
//      Status Register readback.
// =========================================================================

task automatic run_test_48(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 48: Software Write Protection (BP bits) (QSPI-AHB-WPR-48)");
    $display("=======================================================================\n");

    // Use global flash model, set RDSR response to 0x14 (BP = 101)
    tb_top.flash_enable = 1'b1;
    tb_top.flash_quad_mode = 1'b0;
    tb_top.flash.set_pattern(32'h1400_0000);

    begin : master_apb_sequence
        $display("[INFO] --- STEP 0: Hardware Software Reset ---");
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
        repeat(5) @(posedge vif.pclk);

        $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
        tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);

        $display("[INFO] --- STEP 2: Sending WREN (0x06) ---");
        tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; agt.send_write(tx); // 8 bits
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0600_0000; agt.send_write(tx);
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx); // TX ONLY

        repeat(2) @(posedge vif.pclk);
        timeout_ctr = 0;
        do begin
            tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
            @(posedge vif.pclk);
            timeout_ctr++;
        end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

        $display("[INFO] --- STEP 3: Writing Status Register (WRSR 0x01, BP[4:2]=101) ---");
        tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_000F; agt.send_write(tx); // 16 bits
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0114_0000; agt.send_write(tx);
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx); // TX ONLY

        repeat(2) @(posedge vif.pclk);
        timeout_ctr = 0;
        do begin
            tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
            @(posedge vif.pclk);
            timeout_ctr++;
        end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

        $display("[INFO] --- STEP 4: Reading Back Status Register (RDSR 0x05) ---");
        // 8-bit TX (RDSR command), so delay shifting by 8 clocks
        tb_top.flash.set_delay(8);
        tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; agt.send_write(tx); // 8 bits
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0500_0000; agt.send_write(tx);
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; agt.send_write(tx); // TX-then-RX

        repeat(2) @(posedge vif.pclk);
        timeout_ctr = 0;
        do begin
            tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
            @(posedge vif.pclk);
            timeout_ctr++;
        end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

        tx = new(); tx.paddr = 32'h08; agt.send_read(tx);
        val = tx.prdata;
    end

    // FIX: Check [7:0] for 8-bit right-aligned RX data
    if (val[7:0] == 8'h14) begin
        $display("   [PASS] BP bits correctly set. Status Register: 0x%0h\n", val[7:0]);
    end else begin
        $display("   [FAIL] BP bits mismatch. Expected 0x14, Got: 0x%0h\n", val[7:0]);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-AHB-WPR-48");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-WPR-48");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
