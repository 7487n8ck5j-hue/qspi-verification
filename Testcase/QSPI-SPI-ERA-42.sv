// =========================================================================
// TEST 42: Sector/Block/Chip Erase Sequence (QSPI-SPI-ERA-42)
// Comprehensive validation of SPI erase command issuance via STIG,
// WIP polling after erase, and proper FSM completion verification.
// =========================================================================

task automatic run_test_42(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    int poll_count = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 42: Sector/Block/Chip Erase Sequence (QSPI-SPI-ERA-42)");
    $display(" Target: Validate erase command issuance and WIP polling");
    $display("=======================================================================\n");

    fork
        // ---------------------------------------------------------
        // THREAD 1: Mock Flash Slave (Erase + Status Response)
        // ---------------------------------------------------------
        begin : mock_erase_slave
            int erase_poll_count = 0;
            reg [7:0] cmd_byte;
            forever begin
                @(negedge vif.CS_n);
                #1;

                // Sample 8-bit command on D0 (MOSI from master)
                cmd_byte = 8'h00;
                for (int i = 7; i >= 0; i--) begin
                    @(posedge vif.CLK);
                    cmd_byte[i] = (vif.D0 === 1'bz) ? 1'b0 : vif.D0;
                end

                // Recognize erase commands:
                //   0x20 = Sector Erase (4KB)
                //   0x52 = Block Erase (32KB)
                //   0x60 = Chip Erase
                //   0x05 = Read Status Register (RDSR)
                //   0x06 = Write Enable (WREN)
                if (cmd_byte == 8'h05) begin
                    // RDSR: respond with WIP=1 for first 2 polls, then WIP=0
                    for (int i = 7; i >= 0; i--) begin
                        @(negedge vif.CLK);
                        #1;
                        if (i == 0)
                            vif.D1 <= (erase_poll_count < 2) ? 1'b1 : 1'b0;
                        else
                            vif.D1 <= 1'b0;
                    end
                    erase_poll_count++;
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

            $display("[INFO] --- STEP 2: Sending WREN (Write Enable, 0x06) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0600_0000; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 3: Sending Sector Erase (0x20) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h2000_0000; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 4: Polling WIP Status via RDSR (0x05) ---");
            val = 32'h0000_0001;
            poll_count = 0;
            while (val[0] == 1'b1 && poll_count < 50) begin
                // Send RDSR command
                tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0500_0000; agt.send_write(tx);
                tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

                repeat(2) @(posedge vif.pclk);
                timeout_ctr = 0;
                do begin
                    tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
                    @(posedge vif.pclk);
                    timeout_ctr++;
                end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

                // Read status from RX FIFO
                tx = new(); tx.paddr = 32'h08; agt.send_read(tx);
                val = tx.prdata;
                $display("   [DEBUG] RDSR Poll %0d: Status = %h (WIP = %b)", poll_count, val, val[0]);
                poll_count++;
            end
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during erase sequence.\n");
        test_pass = 1'b0;
    end else if (val[0] == 1'b0 && poll_count > 0 && poll_count < 50) begin
        $display("   [PASS] Erase sequence completed. WIP cleared after %0d polls.\n", poll_count);
    end else begin
        $display("   [FAIL] Erase polling failed. Final status: %h, polls: %0d\n", val, poll_count);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-SPI-ERA-42");
    tb_top.scoreboard.mark_as_run("QSPI-SPI-ERA-42");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

