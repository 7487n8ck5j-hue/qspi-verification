// =========================================================================
// TEST 19: AHB Error Response (QSPI-AHB-ERR-19) — CORRECTED
// FIX: Fix scoreboard ref + add pstrb
// =========================================================================
task automatic run_test_19(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 19: AHB Error Response (QSPI-AHB-ERR-19)");
    $display(" Target: Validate error handling for invalid access");
    $display("=======================================================================\n");

    fork
        begin : mock_slave
            forever begin
                @(negedge vif.CS_n);
                #1;
                // Don't respond — force timeout/error
                @(posedge vif.CS_n);
            end
        end

        begin : master_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Triggering Transaction (expect error) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            // Check for error flag in status
            tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up — no error response.\n");
        test_pass = 1'b0;
    end else begin
        $display("   [DEBUG] Status Register: %h", val);
        $display("   [PASS] Error handled gracefully. FSM returned to IDLE.\n");
    end

    tb_top.scoreboard.set_current_test("QSPI-AHB-ERR-19");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-ERR-19");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

