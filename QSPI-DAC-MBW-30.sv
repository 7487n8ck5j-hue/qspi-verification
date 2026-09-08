// =========================================================================
// TEST 30: DAC Multi-Beat Write (QSPI-DAC-MBW-30) — CORRECTED
// FIX: Renamed from QSPI-PHY-MBW-30 to QSPI-DAC-MBW-30
// =========================================================================
task automatic run_test_30(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    int beat_count = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 30: DAC Multi-Beat Write (QSPI-DAC-MBW-30)");
    $display(" Target: Validate multi-beat write through DAC path");
    $display("=======================================================================\n");

    fork
        begin : mock_slave
            forever begin
                @(negedge vif.CS_n);
                #1;
                for (int i=31; i>=0; i--) begin
                    vif.D1 <= 1'b1;
                    if (i > 0) @(negedge vif.CLK);
                end
                beat_count++;
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
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; tx.pstrb = 4'hF; agt.send_write(tx);

            // Send 4 beats of data
            $display("[INFO] --- STEP 2: Sending 4 Data Beats ---");
            for (int i = 0; i < 4; i++) begin
                tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hA5A5_0000 + i; tx.pstrb = 4'hF; agt.send_write(tx);
                tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx);

                repeat(2) @(posedge vif.pclk);
                timeout_ctr = 0;
                do begin
                    tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                    @(posedge vif.pclk);
                    timeout_ctr++;
                end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);
            end
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during multi-beat write.\n");
        test_pass = 1'b0;
    end else if (beat_count >= 4) begin
        $display("   [PASS] Multi-beat write completed. Beats: %0d\n", beat_count);
    end else begin
        $display("   [FAIL] Only %0d beats completed (expected 4).\n", beat_count);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-DAC-MBW-30");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-MBW-30");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

