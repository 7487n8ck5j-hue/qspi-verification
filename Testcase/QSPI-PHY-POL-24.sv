// =========================================================================
// TEST 24: Clock Phase Configuration CPOL/CPHA (QSPI-PHY-POL-24) — REWRITTEN
// FIX: Was custom status polling. Now tests CPOL/CPHA configuration.
// =========================================================================
task automatic run_test_24(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 24: Clock Phase Configuration CPOL/CPHA (QSPI-PHY-POL-24)");
    $display(" Target: Validate CPOL=1, CPHA=1 mode data capture");
    $display("=======================================================================\n");

    fork
        begin : mock_slave_cpol1
            reg [31:0] payload = 32'hF0F0_AAAA;
            forever begin
                @(negedge vif.CS_n);
                #1;
                // Respond on positive edge (CPOL=1, CPHA=1)
                for (int i=31; i>=0; i--) begin
                    @(posedge vif.CLK);
                    #1;
                    vif.D1 <= payload[i];
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

            $display("[INFO] --- STEP 1: Configuring CPOL=1, CPHA=1 ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_000C; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Triggering Read ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; tx.pstrb = 4'hF; agt.send_write(tx);

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
        $display("   [FAIL] FSM locked up with CPOL=1/CPHA=1.\n");
        test_pass = 1'b0;
    end else if (val === 32'hF0F0_AAAA) begin
        $display("   [PASS] CPOL=1/CPHA=1 data captured: %h\n", val);
    end else begin
        $display("   [FAIL] Expected F0F0AAAA, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-PHY-POL-24");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-POL-24");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

