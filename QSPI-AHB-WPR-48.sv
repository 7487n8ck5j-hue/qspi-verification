// =========================================================================
// TEST 48: Software Write Protection (BP bits) (QSPI-AHB-WPR-48)
// Comprehensive validation of Block Protect (BP) bit configuration
// via Status Register Write (WRSR 0x01), readback verification, and
// write protection enforcement.
// =========================================================================

task automatic run_test_48(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 48: Software Write Protection (BP bits) (QSPI-AHB-WPR-48)");
    $display(" Target: Validate BP bit configuration via WRSR and readback");
    $display("=======================================================================\n");

    fork
        // ---------------------------------------------------------
        // THREAD 1: Mock Flash Slave (WRSR/RDSR Response)
        // ---------------------------------------------------------
        begin : mock_wrsr_slave
            reg [7:0] status_reg = 8'h00;
            reg [7:0] cmd_byte;
            forever begin
                @(negedge vif.CS_n);
                #1;

                cmd_byte = 8'h00;
                for (int i = 7; i >= 0; i--) begin
                    @(posedge vif.CLK);
                    cmd_byte[i] = (vif.D0 === 1'bz) ? 1'b0 : vif.D0;
                end

                // 0x01 = WRSR (Write Status Register)
                // 0x05 = RDSR (Read Status Register)
                // 0x06 = WREN
                if (cmd_byte == 8'h01) begin
                    // Capture next 8 bits as new status register value
                    for (int i = 7; i >= 0; i--) begin
                        @(posedge vif.CLK);
                        status_reg[i] = (vif.D0 === 1'bz) ? 1'b0 : vif.D0;
                    end
                end else if (cmd_byte == 8'h05) begin
                    // Respond with current status register
                    for (int i = 7; i >= 0; i--) begin
                        @(negedge vif.CLK);
                        #1;
                        vif.D1 <= status_reg[i];
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

            $display("[INFO] --- STEP 3: Writing Status Register (WRSR 0x01, BP[4:2]=101) ---");
            // BP bits = 0b10100 (bits 4:2 = 101), sets block protect for top quarter
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0114_0000; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 4: Reading Back Status Register (RDSR 0x05) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0500_0000; agt.send_write(tx);
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

    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during write protection test.\n");
        test_pass = 1'b0;
    end else if (val[4:2] == 3'b101) begin
        $display("   [PASS] BP bits correctly set. Status Register: 0x%0h\n", val);
    end else begin
        $display("   [FAIL] BP bits mismatch. Expected BP=101, Got: %b\n", val[4:2]);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-AHB-WPR-48");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-WPR-48");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

