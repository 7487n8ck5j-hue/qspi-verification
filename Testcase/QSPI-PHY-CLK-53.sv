// =========================================================================
// TEST 53: Dynamic Baud Rate Change (QSPI-PHY-CLK-53)
// Validates that the SPI clock divider can be dynamically reconfigured
// between transfers and the new baud rate takes effect immediately.
// =========================================================================

task automatic run_test_53(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    int pclk_count_1 = 0;
    int pclk_count_2 = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 53: Dynamic Baud Rate Change (QSPI-PHY-CLK-53)");
    $display(" Target: Validate dynamic clock divider reconfiguration");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Divider = 4 (Period = 10 pclk) ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hFF00_FF00; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

    fork
        begin : clk_measure_1
            @(posedge vif.CLK);
            pclk_count_1 = 0;
            fork
                begin @(posedge vif.CLK); end
                begin forever begin @(posedge vif.pclk); pclk_count_1++; end end
            join_any
            disable fork;
        end
        begin : timeout_1
            repeat(400) @(posedge vif.pclk);
        end
    join_any
    disable fork;

    $display("   [DEBUG] Divider=4: Measured period = %0d pclk cycles", pclk_count_1);

    repeat(2) @(posedge vif.pclk);
    timeout_ctr = 0;
    do begin
        tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
        @(posedge vif.pclk);
        timeout_ctr++;
    end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

    $display("[INFO] --- STEP 2: Reconfiguring Divider = 2 (Period = 6 pclk) ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0002; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hFF00_FF00; agt.send_write(tx);
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

    fork
        begin : clk_measure_2
            @(posedge vif.CLK);
            pclk_count_2 = 0;
            fork
                begin @(posedge vif.CLK); end
                begin forever begin @(posedge vif.pclk); pclk_count_2++; end end
            join_any
            disable fork;
        end
        begin : timeout_2
            repeat(400) @(posedge vif.pclk);
        end
    join_any
    disable fork;

    $display("   [DEBUG] Divider=2: Measured period = %0d pclk cycles", pclk_count_2);

    $display("[INFO] --- STEP 3: Final Result Evaluation ---");
    if (pclk_count_1 == 10 && pclk_count_2 == 6) begin
        $display("   [PASS] Dynamic baud rate change verified. Div4=%0d, Div2=%0d\n", pclk_count_1, pclk_count_2);
    end else begin
        $display("   [FAIL] Baud rate mismatch. Expected Div4=10 Div2=6, Got: %0d and %0d\n", pclk_count_1, pclk_count_2);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-PHY-CLK-53");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-CLK-53");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
