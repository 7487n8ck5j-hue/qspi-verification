// =========================================================================
// TEST 12: Reset During Transfer Abort (QSPI-PHY-RST-12) — REWRITTEN
// FIX: Was max toggle pressure test. Now tests mid-transfer reset abort.
// =========================================================================
task automatic run_test_12(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 12: Reset During Transfer Abort (QSPI-PHY-RST-12)");
    $display(" Target: Validate FSM returns to IDLE after mid-transfer reset");
    $display("=======================================================================\n");

    fork
        begin : mock_slave
            reg [7:0] payload = 8'hCC;
            forever begin
                @(negedge vif.CS_n);
                #1;
                for (int i=7; i>=0; i--) begin
                    vif.D1 <= payload[i];
                    if (i > 0) @(negedge vif.CLK);
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

            $display("[INFO] --- STEP 2: Starting SPI Transaction ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx);

            // Wait a few cycles then assert reset mid-transfer
            repeat(3) @(posedge vif.pclk);

            $display("[INFO] --- STEP 3: Asserting Hardware Reset Mid-Transfer ---");
            vif.presetn = 1'b0;
            repeat(10) @(posedge vif.pclk);
            vif.presetn = 1'b1;
            $display("[INFO] --- STEP 4: Reset Released, Checking FSM Recovery ---");

            repeat(5) @(posedge vif.pclk);

            // Check Status Register — FSM should be IDLE (bit 11 = 0)
            tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
            val = tx.prdata;

            if (val[11] == 1'b0) begin
                $display("   [DEBUG] FSM is IDLE after reset. Status: %h", val);
            end else begin
                $display("   [DEBUG] FSM still BUSY after reset. Status: %h", val);
            end

            $display("[INFO] --- STEP 5: Attempting New Transaction After Reset ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM did not recover after mid-transfer reset.\n");
        test_pass = 1'b0;
    end else if (val === 32'h0000_00CC) begin
        $display("   [PASS] FSM recovered after reset. Data: %h\n", val);
    end else begin
        $display("   [FAIL] Post-reset read mismatch. Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-PHY-RST-12");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-RST-12");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

