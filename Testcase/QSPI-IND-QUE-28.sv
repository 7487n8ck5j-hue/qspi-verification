// =========================================================================
// TEST 28: INDAC Dual Queue Mechanism (QSPI-IND-QUE-28) — REWRITTEN
// FIX: Was interrupt mask test with old ID. Now tests INDAC dual queue.
// =========================================================================
task automatic run_test_28(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 28: INDAC Dual Queue Mechanism (QSPI-IND-QUE-28)");
    $display(" Target: Validate indirect queue with read and write sequencing");
    $display("=======================================================================\n");

    fork
        begin : mock_slave
            reg [31:0] payload = 32'h8BAD_F00D;
            forever begin
                @(negedge vif.CS_n);
                #1;
                for (int i=31; i>=0; i--) begin
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

            // Queue 1: Write command
            $display("[INFO] --- STEP 2: Queue Write Command ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0600_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            // Queue 2: Read command
            $display("[INFO] --- STEP 3: Queue Read Command ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 4: Reading Queued Data ---");
            tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during dual queue.\n");
        test_pass = 1'b0;
    end else if (val === 32'h8BAD_F00D) begin
        $display("   [PASS] Dual queue read data: %h\n", val);
    end else begin
        $display("   [FAIL] Expected 8BADF00D, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-IND-QUE-28");
    tb_top.scoreboard.mark_as_run("QSPI-IND-QUE-28");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

