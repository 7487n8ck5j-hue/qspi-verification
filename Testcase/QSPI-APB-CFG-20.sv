// =========================================================================
// TEST 20: SPI Configuration Register (QSPI-APB-CFG-20) — CORRECTED
// FIX: Renamed from QSPI-SPI-CFG-20 to QSPI-APB-CFG-20
// =========================================================================
task automatic run_test_20(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 20: SPI Configuration Register (QSPI-APB-CFG-20)");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Writing Configuration Register ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h14; tx.pwdata = 32'h0000_0008; tx.pstrb = 4'hF; agt.send_write(tx);

    repeat(3) @(posedge vif.pclk);

    $display("[INFO] --- STEP 2: Readback Configuration ---");
    tx = new(); tx.paddr = 32'h0C; tx.pstrb = 4'hF; agt.send_read(tx);
    val = tx.prdata;

    if (val === 32'h0000_0004) begin
        $display("   [PASS] Config register readback correct: %h\n", val);
    end else begin
        $display("   [FAIL] Config mismatch. Expected 00000004, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-CFG-20");
    tb_top.scoreboard.mark_as_run("QSPI-APB-CFG-20");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

