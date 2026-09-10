// =========================================================================
// TEST 31: DAC XIP F1FEline Read (QSPI-DAC-PPL-31)
// FIX: Changed flash delay to 0 because the Master is configured for 
//      RX-ONLY mode (0x0401), meaning there is no TX phase to wait out.
// =========================================================================
task automatic run_test_31(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 31: DAC XIP F1FEline Read (QSPI-DAC-PPL-31)");
    $display("=======================================================================\n");

    // Use global flash model
    tb_top.flash_enable = 1'b1;
    tb_top.flash_quad_mode = 1'b1;
    tb_top.flash.set_pattern(32'hF1FE_3131);
    
    // FIX: RX-Only mode immediately begins reading. Delay must be 0.
    tb_top.flash.set_delay(0);

    begin : master_sequence
        $display("[INFO] --- STEP 0: Hardware Software Reset ---");
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
        repeat(5) @(posedge vif.pclk);

        $display("[INFO] --- STEP 1: Configuring Master ---");
        tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
        tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; tx.pstrb = 4'hF; agt.send_write(tx);
        
        // Clear dummy cycles to prevent cross-test leakage
        tx = new(); tx.paddr = 32'h14; tx.pwdata = 32'h0000_0000; tx.pstrb = 4'hF; agt.send_write(tx);

        $display("[INFO] --- STEP 2: Triggering Quad F1FEline Read ---");
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
        // Valid Quad RX-ONLY mode (0x0401)
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0401; tx.pstrb = 4'hF; agt.send_write(tx);

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

    tb_top.flash_quad_mode = 1'b0;

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up.\n");
        test_pass = 1'b0;
    end else if (val === 32'hF1FE_3131) begin
        $display("   [PASS] F1FEline read data: %h\n", val);
    end else begin
        $display("   [FAIL] Expected F1FE3131, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-DAC-PPL-31");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-PPL-31");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
