// =========================================================================
// TEST 45: JEDEC ID Read (RDID 0x9F) (QSPI-APB-ID-45)
// FIX: Updated result evaluation to slice val[23:0] because the RX FIFO 
//      right-aligns (LSB-aligns) incoming data that is less than 32 bits.
// =========================================================================

task automatic run_test_45(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 45: JEDEC ID Read (RDID 0x9F) (QSPI-APB-ID-45)");
    $display(" Target: Validate JEDEC ID command and 3-byte response capture");
    $display("=======================================================================\n");

    tb_top.flash_enable    = 1'b1;
    tb_top.flash_quad_mode = 1'b0;
    // JEDEC ID: Manufacturer=0xEF, Device=0x4018 (MSB-aligned for flash model)
    tb_top.flash.set_pattern(32'hEF40_1800);
    tb_top.flash.set_delay(24); // Match the 24-bit TX phase (XFERLEN = 23)

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
    // Transfer Length = 23 (24 cycles = 3 bytes of JEDEC ID response)
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0017; agt.send_write(tx);

    $display("[INFO] --- STEP 2: Sending RDID Command (0x9F) via TX ---");
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h9F00_0000; agt.send_write(tx);
    // TX-then-RX Mode (Bits 14:13=10, Bit 0=1 -> 0x4001)
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; agt.send_write(tx);

    $display("[INFO] --- STEP 3: Polling FSM Status ---");
    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
        @(posedge vif.pclk);
        timeout_ctr++;
    end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

    $display("[INFO] --- STEP 4: Extracting JEDEC ID from RX FIFO ---");
    tx = new(); tx.paddr = 32'h08; agt.send_read(tx);
    val = tx.prdata;

    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during JEDEC ID read.\n");
        test_pass = 1'b0;
    // FIX: Check [23:0] for 24-bit right-aligned RX data
    end else if (val[23:0] === 24'hEF4018) begin
        $display("   [PASS] JEDEC ID captured. Manufacturer=0x%0h, Device=0x%0h%0h\n",
                 val[23:16], val[15:8], val[7:0]);
    end else begin
        $display("   [FAIL] JEDEC ID mismatch. Expected 0xEF4018, Got: 0x%0h\n", val[23:0]);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-ID-45");
    tb_top.scoreboard.mark_as_run("QSPI-APB-ID-45");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
