// =========================================================================
// TEST 35: AHB Address Decode Adapter (QSPI-AHB-DEC-35)
// FIX: Updated Transfer Length to 0x1F (32 bits) to accommodate the full
//      8-bit command + 24-bit address TX phase, and 32-bit RX phase. 
//      Aligned the flash model delay to 32 clocks.
// =========================================================================
task automatic run_test_35(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 35: AHB Address Decode Adapter (QSPI-AHB-DEC-35)");
    $display(" Target: Validate address decode for memory-mapped QSPI access");
    $display("=======================================================================\n");

    // Use global flash model
    tb_top.flash_enable = 1'b1;
    tb_top.flash_quad_mode = 1'b0;
    tb_top.flash.set_pattern(32'hDEC0_DE35);
    
    // FIX: Master sends 32 bits (8-bit cmd + 24-bit addr). Wait 32 clocks.
    tb_top.flash.set_delay(32);

    begin : master_sequence
        $display("[INFO] --- STEP 0: Hardware Software Reset ---");
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
        repeat(5) @(posedge vif.pclk);

        $display("[INFO] --- STEP 1: Configuring Master ---");
        tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
        // FIX: Transfer Length = 31 (32 clock cycles for both TX and RX phases)
        tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; tx.pstrb = 4'hF; agt.send_write(tx);
        
        // Clear dummy cycles
        tx = new(); tx.paddr = 32'h14; tx.pwdata = 32'h0000_0000; tx.pstrb = 4'hF; agt.send_write(tx);

        $display("[INFO] --- STEP 2: Setting Address Window ---");
        tx = new(); tx.paddr = 32'h20; tx.pwdata = 32'h0000_0000; tx.pstrb = 4'hF; agt.send_write(tx);
        tx = new(); tx.paddr = 32'h24; tx.pwdata = 32'h0000_FFFF; tx.pstrb = 4'hF; agt.send_write(tx);

        $display("[INFO] --- STEP 3: Triggering Memory-Mapped Read ---");
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
        // TX-then-RX Mode
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
        $display("   [FAIL] FSM locked up during address decode.\n");
        test_pass = 1'b0;
    end else if (val === 32'hDEC0_DE35) begin
        $display("   [PASS] Address decode read data: %h\n", val);
    end else begin
        $display("   [FAIL] Expected DEC0_DE35, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-AHB-DEC-35");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-DEC-35");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
