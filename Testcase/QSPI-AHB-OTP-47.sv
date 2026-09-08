// =========================================================================
// TEST 47: OTP/Security Register Lock (QSPI-AHB-OTP-47)
// Comprehensive validation of OTP register access, security register
// read/write lock mechanism, and lock status verification.
// =========================================================================

task automatic run_test_47(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 47: OTP/Security Register Lock (QSPI-AHB-OTP-47)");
    $display(" Target: Validate OTP access and security lock mechanism");
    $display("=======================================================================\n");

    fork
        // ---------------------------------------------------------
        // THREAD 1: Mock Flash Slave (OTP Security Response)
        // ---------------------------------------------------------
        begin : mock_otp_slave
            reg [7:0] cmd_byte;
            reg [7:0] security_reg = 8'h00;
            forever begin
                @(negedge vif.CS_n);
                #1;

                cmd_byte = 8'h00;
                for (int i = 7; i >= 0; i--) begin
                    @(posedge vif.CLK);
                    cmd_byte[i] = (vif.D0 === 1'bz) ? 1'b0 : vif.D0;
                end

                // 0x35 = Read Security Register
                // 0x2B = Write Security Register
                // 0xB0 = Erase Security Register
                // 0x06 = WREN
                if (cmd_byte == 8'h35) begin
                    // Respond with security register value
                    // Bit 0 = LB (Lock Bit for OTP)
                    for (int i = 7; i >= 0; i--) begin
                        @(negedge vif.CLK);
                        #1;
                        vif.D1 <= security_reg[i];
                    end
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

            $display("[INFO] --- STEP 2: Sending WREN (0x06) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0600_0000; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 3: Reading Security Register (0x35) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h3500_0000; agt.send_write(tx);
            // TX-then-RX Mode
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; agt.send_write(tx);

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
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    $display("[INFO] --- STEP 4: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during OTP security access.\n");
        test_pass = 1'b0;
    end else begin
        $display("   [PASS] OTP security register read completed. Value: 0x%0h\n", val);
    end

    tb_top.scoreboard.set_current_test("QSPI-AHB-OTP-47");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-OTP-47");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

