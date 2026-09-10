// =========================================================================
// TEST 09: DDR Protocol Parameter Sync (QSPI-PHY-DDR-09)
// =========================================================================
task automatic run_test_09(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 09: DDR Protocol Parameter Sync (QSPI-PHY-DDR-09)");
    $display(" Target: Validate Quad parameter configuration and data capture");
    $display("=======================================================================\n");

    // 32-bit TX in Quad Mode = 8 clock cycles
    tb_top.flash_enable    = 1'b1;
    tb_top.flash_quad_mode = 1'b1;
    tb_top.flash.set_pattern(32'hDDDD_9999);
    tb_top.flash.set_delay(8);

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; tx.pstrb = 4'hF; agt.send_write(tx);

    $display("[INFO] --- STEP 2: Triggering Quad Read ---");
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hED00_0000; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0401; tx.pstrb = 4'hF; agt.send_write(tx);

    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
        @(posedge vif.pclk);
        timeout_ctr++;
    end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

    $display("[INFO] --- STEP 3: Reading Payload from RX FIFO ---");
    tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
    val = tx.prdata;

    tb_top.flash_quad_mode = 1'b0;

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up.\n");
        test_pass = 1'b0;
    end else if (val === 32'hDDDD_9999) begin
        $display("   [PASS] Data captured correctly: %h\n", val);
    end else begin
        $display("   [FAIL] Expected DDDD9999, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-PHY-DDR-09");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-DDR-09");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
