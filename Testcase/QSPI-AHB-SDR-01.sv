// =========================================================================
// TEST 01: Boot Payload Validation (QSPI-AHB-SDR-01) — CORRECTED
// FIX: Send actual READ opcode 0x03 instead of 0x00
// =========================================================================
task automatic run_test_01(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    int cs_toggles = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 01: Boot Payload Validation (QSPI-AHB-SDR-01)");
    $display("=======================================================================\n");

    repeat(5) @(posedge vif.pclk);

    fork
        begin : cs_monitor
            forever begin
                @(negedge vif.CS_n);
                cs_toggles++;
            end
        end

        begin : spi_sdr_slave
            reg [7:0] payload = 8'hB0;
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

        begin : test_sequence
            $display("[INFO] Step 1: Configuring QSPI Master Architecture...");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);

            // FIX: Load TX FIFO with actual READ opcode 0x03 (was 0x00)
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);

            $display("[INFO] Step 2: Triggering SPI Transaction...");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0005; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            $display("[INFO] Step 3: Waiting for FSM to complete...");
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            if (timeout_ctr >= 1000) begin
                $display("   [FAIL] Hardware locked up. FSM did not return to IDLE.");
                test_pass = 1'b0;
            end

            $display("[INFO] Step 4: Reading fetched payload from RX FIFO...");
            tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    $display("   [DEBUG] CS_n Toggle Count: %0d", cs_toggles);
    if (cs_toggles == 0) begin
        $display("   [FAIL] CS_n never asserted.");
        test_pass = 1'b0;
    end else if (val === 32'h0000_00B0) begin
        $display("   [PASS] Boot Payload Validated: %h\n", val);
    end else begin
        $display("   [FAIL] Expected 0000_00B0, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-AHB-SDR-01");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-SDR-01");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

