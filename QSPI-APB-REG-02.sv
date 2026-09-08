// =========================================================================
// TEST 02: STIG Standard Transfer (QSPI-APB-REG-02) — REWRITTEN
// FIX: Complete rewrite. Was testing FLASH_RST_n (TC16's scope).
//      Now correctly tests STIG command transfer: WREN + RDSR.
// =========================================================================
task automatic run_test_02(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 02: STIG Standard Transfer (QSPI-APB-REG-02)");
    $display(" Target: Validate WREN + RDSR command issuance via STIG");
    $display("=======================================================================\n");

    fork
        // Mock slave: recognizes WREN (0x06) and RDSR (0x05)
        begin : mock_stig_slave
            reg [7:0] cmd_byte;
            int rdsr_count = 0;
            forever begin
                @(negedge vif.CS_n);
                #1;
                cmd_byte = 8'h00;
                for (int i = 7; i >= 0; i--) begin
                    @(posedge vif.CLK);
                    cmd_byte[i] = (vif.D0 === 1'bz) ? 1'b0 : vif.D0;
                end

                if (cmd_byte == 8'h05) begin
                    // RDSR: respond with WIP=1 for first poll, then WIP=0
                    for (int i = 7; i >= 0; i--) begin
                        @(negedge vif.CLK);
                        #1;
                        if (i == 0)
                            vif.D1 <= (rdsr_count < 1) ? 1'b1 : 1'b0;
                        else
                            vif.D1 <= 1'b0;
                    end
                    rdsr_count++;
                end

                @(posedge vif.CS_n);
                #1;
                vif.D1 <= 1'bz;
            end
        end

        begin : master_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Sending WREN (0x06) via TX FIFO ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0600_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 3: Sending RDSR (0x05) via TX-then-RX ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0500_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 4: Reading Status from RX FIFO ---");
            tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during STIG transfer.\n");
        test_pass = 1'b0;
    end else if (val[0] == 1'b0) begin
        $display("   [PASS] STIG transfer completed. RDSR returned WIP=0 (ready). Value: 0x%0h\n", val);
    end else begin
        $display("   [FAIL] RDSR still shows WIP=1. Value: 0x%0h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-REG-02");
    tb_top.scoreboard.mark_as_run("QSPI-APB-REG-02");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

