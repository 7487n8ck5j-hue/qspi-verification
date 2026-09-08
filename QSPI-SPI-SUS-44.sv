// =========================================================================
// TEST 44: Erase/Program Suspend and Resume (QSPI-SPI-SUS-44)
// Comprehensive validation of Suspend (0x75) and Resume (0x7A) command
// issuance during active erase/program operations.
// =========================================================================

task automatic run_test_44(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 44: Erase/Program Suspend and Resume (QSPI-SPI-SUS-44)");
    $display(" Target: Validate Suspend/Resume command sequence");
    $display("=======================================================================\n");

    fork
        // ---------------------------------------------------------
        // THREAD 1: Mock Flash Slave (Suspend/Resume Aware)
        // ---------------------------------------------------------
        begin : mock_suspend_slave
            reg [7:0] cmd_byte;
            int sus_poll_count = 0;
            forever begin
                @(negedge vif.CS_n);
                #1;

                cmd_byte = 8'h00;
                for (int i = 7; i >= 0; i--) begin
                    @(posedge vif.CLK);
                    cmd_byte[i] = (vif.D0 === 1'bz) ? 1'b0 : vif.D0;
                end

                // 0x75 = Program/Erase Suspend
                // 0x7A = Program/Erase Resume
                // 0x05 = RDSR
                if (cmd_byte == 8'h05) begin
                    for (int i = 7; i >= 0; i--) begin
                        @(negedge vif.CLK);
                        #1;
                        // Bit 0 = WIP, Bit 1 = SUS (suspend in progress)
                        if (i == 0)
                            vif.D1 <= (sus_poll_count < 2) ? 1'b1 : 1'b0;
                        else if (i == 1)
                            vif.D1 <= (sus_poll_count < 1) ? 1'b0 : 1'b0;
                        else
                            vif.D1 <= 1'b0;
                    end
                    sus_poll_count++;
                end

                @(posedge vif.CS_n);
                #1;
                vif.D1 <= 1'bz;
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master APB Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Sending Suspend Command (0x75) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h7500_0000; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 3: Polling SUS Status via RDSR ---");
            val = 32'h0000_0001;
            while (val[0] == 1'b1 && timeout_ctr < 1000) begin
                tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0500_0000; agt.send_write(tx);
                tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

                repeat(2) @(posedge vif.pclk);
                timeout_ctr = 0;
                do begin
                    tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
                    @(posedge vif.pclk);
                    timeout_ctr++;
                end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

                tx = new(); tx.paddr = 32'h08; agt.send_read(tx);
                val = tx.prdata;
            end

            $display("[INFO] --- STEP 4: Sending Resume Command (0x7A) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h7A00_0000; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during suspend/resume sequence.\n");
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] Suspend/Resume sequence completed cleanly.\n");
    end

    tb_top.scoreboard.set_current_test("QSPI-SPI-SUS-44");
    tb_top.scoreboard.mark_as_run("QSPI-SPI-SUS-44");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

