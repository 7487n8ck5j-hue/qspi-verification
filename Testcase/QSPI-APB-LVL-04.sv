// =========================================================================
// TEST 04: Legacy SPI Mode FIFO Thresholds (QSPI-APB-LVL-04) — CORRECTED
// FIX: Replace tb_top.dut.* with Status Register (0x18) reads
// =========================================================================
task automatic run_test_04(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] status_val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 04: Legacy SPI Mode FIFO Thresholds (QSPI-APB-LVL-04)");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Clock Divider ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);

    $display("[INFO] --- STEP 2: Filling TX FIFO (4 words) ---");
    for (int i = 0; i < 4; i++) begin
        tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hA5A5_0000 + i; tx.pstrb = 4'hF; agt.send_write(tx);
    end

    repeat(5) @(posedge vif.pclk);

    // FIX: Read FIFO count from Status Register (0x18) instead of tb_top.dut.*
    $display("[INFO] --- STEP 3: Reading TX FIFO Count via Status Register ---");
    tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
    status_val = tx.prdata;
    $display("   [DEBUG] Status Register: 0x%0h, TX FIFO Count: %0d", status_val, status_val[3:0]);

    if (status_val[3:0] == 4'd4) begin
        $display("   [PASS] TX FIFO Count = 4 (threshold met).\n");
    end else begin
        $display("   [FAIL] TX FIFO Count = %0d, expected 4.\n", status_val[3:0]);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-LVL-04");
    tb_top.scoreboard.mark_as_run("QSPI-APB-LVL-04");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

