task automatic run_test_08(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val1, val2;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 08: Continuous XIP Mode Entry (QSPI-DAC-XIP-08)");
    $display("=======================================================================\n");

    tb_top.flash_enable    = 1'b1;
    tb_top.flash_quad_mode = 1'b0;

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; tx.pstrb = 4'hF; agt.send_write(tx);

    $display("[INFO] --- STEP 2: First Read (Mode 2'b10: TX+RX) ---");
    tb_top.flash.set_pattern(32'hAAAA_1111);
    tb_top.flash.set_delay(32); // 32-bit TX phase
    
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
    val1 = tx.prdata;

    $display("[INFO] --- STEP 3: Second Read (XIP Mode 2'b00: RX-ONLY) ---");
    tb_top.flash.set_pattern(32'hBBBB_2222);
    // Even in RX-ONLY, master burns 8 clocks dropping the non-existent instruction
    tb_top.flash.set_delay(8); 
    
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx);

    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
        @(posedge vif.pclk);
        timeout_ctr++;
    end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

    tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
    val2 = tx.prdata;

    if (val1 === 32'hAAAA_1111 && val2 === 32'hBBBB_2222) begin
        $display("   [PASS] XIP continuous read verified. Read1: %h, Read2: %h\n", val1, val2);
    end else begin
        $display("   [FAIL] XIP read mismatch. Read1: %h, Read2: %h\n", val1, val2);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-DAC-XIP-08");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-XIP-08");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
