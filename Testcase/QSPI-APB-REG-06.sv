// =========================================================================
// TEST 06: SPI Fast Read Instruction Verification (QSPI-APB-REG-06) — CORRECTED
// FIX: Add Quad mode testing + strengthen pass criteria
// =========================================================================
task automatic run_test_06(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val_std, val_quad;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 06: SPI Fast Read Instruction Verification (QSPI-APB-REG-06)");
    $display("=======================================================================\n");

    fork
        begin : mock_read_slave
            reg [31:0] payload = 32'hCAFE_BABE;
            reg [3:0]  slave_drv;
            forever begin
                @(negedge vif.CS_n);
                repeat(6) @(negedge vif.CLK);
                #1;
                for (int i=7; i>=0; i--) begin
                    slave_drv = (payload >> (i*4)) & 4'hF;
                    vif.D3 <= slave_drv[3]; vif.D2 <= slave_drv[2];
                    vif.D1 <= slave_drv[1]; vif.D0 <= slave_drv[0];
                    if (i > 0) @(negedge vif.CLK);
                end
                @(posedge vif.CS_n);
                #1;
                vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz;
            end
        end

        begin : master_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; tx.pstrb = 4'hF; agt.send_write(tx);

            // --- Standard SPI Read ---
            $display("[INFO] --- STEP 2: Standard SPI Read (0x0B Fast Read) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0B00_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
            val_std = tx.prdata;
            $display("   [DEBUG] Standard Read: 0x%0h", val_std);

            // --- FIX: Quad SPI Read ---
            $display("[INFO] --- STEP 3: Quad SPI Read (0x6B Quad Fast Read) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h6B00_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            // FIX: Use valid Quad RX mode (0x0401) instead of hallucinated bit 14
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0401; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
            val_quad = tx.prdata;
            $display("   [DEBUG] Quad Read: 0x%0h", val_quad);
        end
    join_any

    disable fork;
    vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz;

    // FIX: Strengthened pass criteria — exact match, not just non-zero
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up.\n");
        test_pass = 1'b0;
    end else if (val_std === 32'hCAFE_BABE && val_quad === 32'hCAFE_BABE) begin
        $display("   [PASS] Both Standard and Quad reads returned correct data: %h\n", val_std);
    end else begin
        $display("   [FAIL] Data mismatch. Std: %h, Quad: %h (expected CAFEBABE)\n", val_std, val_quad);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-REG-06");
    tb_top.scoreboard.mark_as_run("QSPI-APB-REG-06");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

