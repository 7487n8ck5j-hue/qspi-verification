// =========================================================================
// TEST 03: Status Register Polling (WIP Check) (QSPI-PHY-POL-03) — CORRECTED
// FIX: Poll Status Register (0x18) bit 11 for busy instead of CTRL (0x00) bit 0
// =========================================================================
task automatic run_test_03(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int poll_count = 0;
    logic [31:0] val = 32'h0000_0001;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 03: Status Register Polling (WIP Check) (QSPI-PHY-POL-03)");
    $display("=======================================================================\n");

    fork
        begin : custom_mock_slave
            forever begin
                @(negedge vif.CS_n);
                #1;
                for (int i=7; i>=0; i--) begin
                    if (i == 0 && poll_count < 3)
                        vif.D1 <= 1'b1;
                    else
                        vif.D1 <= 1'b0;
                    if (i > 0) @(negedge vif.CLK);
                end
                poll_count++;
                @(posedge vif.CS_n);
                #1;
                vif.D1 <= 1'bz;
            end
        end

        begin : master_apb_polling
            $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Initiating Polling Loop ---");
            val = 32'h0000_0001;
            timeout_ctr = 0;
            while (val[0] == 1'b1 && timeout_ctr < 50) begin
                $display("   [DEBUG] Polling Attempt %0d...", timeout_ctr + 1);

                tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx);

                repeat(10) @(posedge vif.pclk);

                // FIX: Poll Status Register (0x18) bit 11 for FSM busy
                do begin
                    tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                    @(posedge vif.pclk);
                end while (tx.prdata[11] == 1'b1);

                tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
                val = tx.prdata;
                $display("   [DEBUG] Status Register Readback: %h (WIP = %b)", val, val[0]);
                timeout_ctr++;
            end
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    if (val[0] == 1'b0 && timeout_ctr > 0 && timeout_ctr < 50) begin
        $display("   [PASS] Flash READY. Exited after %0d polls.\n", timeout_ctr);
    end else begin
        $display("   [FAIL] Polling failed. Final: %h, Polls: %0d\n", val, timeout_ctr);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-PHY-POL-03");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-POL-03");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

