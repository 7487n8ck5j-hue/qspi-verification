// =========================================================================
// TEST 06: SPI Fast Read Instruction Verification (QSPI-APB-REG-06)
// FIX: Adjusted flash rx_delay to 8 for the Quad read. The Master's Quad 
//      Enable bit forces the 32-bit TX phase to execute in 8 clock cycles.
// =========================================================================
task automatic run_test_06(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val_std, val_quad;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 06: SPI Fast Read Instruction Verification (QSPI-APB-REG-06)");
    $display("=======================================================================\n");

    tb_top.flash_enable = 1'b1;
    tb_top.flash.set_pattern(32'hCAFE_BABE);

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
    // XFERLEN = 31 (32 bits per phase)
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; tx.pstrb = 4'hF; agt.send_write(tx);

    $display("[INFO] --- STEP 2: Standard SPI Read (0x0B Fast Read) ---");
    tb_top.flash_quad_mode = 1'b0;
    // Single TX phase: 32 bits = 32 clocks
    tb_top.flash.set_delay(32); 
    
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0B00_0000; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; tx.pstrb = 4'hF; agt.send_write(tx); // TX-then-RX

    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
        @(posedge vif.pclk);
        timeout_ctr++;
    end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

    tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
    val_std = tx.prdata;

    $display("[INFO] --- STEP 3: Quad SPI Read (0x6B Quad Fast Read) ---");
    tb_top.flash_quad_mode = 1'b1;
    // FIX: Quad TX phase: 32 bits / 4 pins = 8 clocks
    tb_top.flash.set_delay(8); 
    
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h6B00_0000; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4401; tx.pstrb = 4'hF; agt.send_write(tx); // TX-then-RX, Quad Enabled

    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
        @(posedge vif.pclk);
        timeout_ctr++;
    end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

    tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
    val_quad = tx.prdata;
    
    // Restore default state
    tb_top.flash_quad_mode = 1'b0;

    if (val_std === 32'hCAFE_BABE && val_quad === 32'hCAFE_BABE) begin
        $display("   [PASS] Both Standard and Quad reads returned correct data: %h\n", val_std);
    end else begin
        $display("   [FAIL] Data mismatch. Std: %h, Quad: %h\n", val_std, val_quad);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-REG-06");
    tb_top.scoreboard.mark_as_run("QSPI-APB-REG-06");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
