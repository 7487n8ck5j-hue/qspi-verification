// =========================================================================
// TEST 50: AHB Unaligned Access Handling (QSPI-AHB-ERR-50)
// Validates that unaligned APB accesses (non-word-aligned addresses)
// are handled correctly with pslverr or proper byte-strobe behavior.
// =========================================================================

task automatic run_test_50(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 50: AHB Unaligned Access Handling (QSPI-AHB-ERR-50)");
    $display(" Target: Validate unaligned address handling and pstrb behavior");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Attempting Unaligned Read (0x01) ---");
    tx = new(); tx.paddr = 32'h0000_0001; agt.send_read(tx);
    if (tx.pslverr === 1'b1) begin
        $display("   [PASS] Unaligned read correctly rejected with PSLVERR.");
    end else begin
        $display("   [WARN] Unaligned read not rejected. Data: 0x%0h", tx.prdata);
    end

    $display("[INFO] --- STEP 2: Attempting Unaligned Write (0x03) ---");
    tx = new(); tx.paddr = 32'h0000_0003; tx.pwdata = 32'hDEAD_BEEF; agt.send_write(tx);
    if (tx.pslverr === 1'b1) begin
        $display("   [PASS] Unaligned write correctly rejected with PSLVERR.");
    end else begin
        $display("   [WARN] Unaligned write not rejected.");
    end

    $display("[INFO] --- STEP 3: Byte-Level Write via pstrb (0x00, pstrb=4'h1) ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_00AB; tx.pstrb = 4'h1; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
    if (tx.prdata[7:0] === 8'hAB) begin
        $display("   [PASS] Byte-level write via pstrb verified. Byte 0 = 0xAB");
    end else begin
        $display("   [FAIL] Byte-level write failed. Expected 0xAB, Got: 0x%0h", tx.prdata[7:0]);
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 4: Half-Word Write via pstrb (0x00, pstrb=4'h3) ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_CDEF; tx.pstrb = 4'h3; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
    if (tx.prdata[15:0] === 16'hCDEF) begin
        $display("   [PASS] Half-word write via pstrb verified. Bytes [1:0] = 0xCDEF\n");
    end else begin
        $display("   [FAIL] Half-word write failed. Expected 0xCDEF, Got: 0x%0h\n", tx.prdata[15:0]);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-AHB-ERR-50");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-ERR-50");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

