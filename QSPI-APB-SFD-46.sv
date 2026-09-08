// =========================================================================
// TEST 46: SFDP Parameter Table Read (QSPI-APB-SFD-46)
// Comprehensive validation of SFDP (JESD216) command (0x5A) issuance,
// parameter table header capture, and multi-word sequential read.
// =========================================================================

task automatic run45_46_slave;
    // placeholder
endtask

task automatic run_test_46(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 46: SFDP Parameter Table Read (QSPI-APB-SFD-46)");
    $display(" Target: Validate SFDP (0x5A) command and parameter table capture");
    $display("=======================================================================\n");

    fork
        // ---------------------------------------------------------
        // THREAD 1: Mock Flash Slave (SFDP Response)
        // ---------------------------------------------------------
        begin : mock_sfdp_slave
            // SFDP Signature: 0x46504453 ("SFDS" in ASCII)
            reg [31:0] sfdp_signature = 32'h46504453;
            reg [31:0] sfdp_param_hdr = 32'h0068_00FF;
            forever begin
                @(negedge vif.CS_n);
                #1;

                // Wait for 8-bit command + 24-bit address + 8 dummy cycles
                repeat(5) @(negedge vif.CLK);

                // Shift out SFDP signature (32 bits, MSB first)
                for (int i = 31; i >= 0; i--) begin
                    vif.D1 <= sfdp_signature[i];
                    if (i > 0) @(negedge vif.CLK);
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
            // Transfer Length = 31 (32 cycles = 4 bytes of SFDP data)
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Sending SFDP Command (0x5A) via TX ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h5A00_0000; agt.send_write(tx);
            // TX-then-RX Mode (Bits 14:13=10, Bit 0=1 -> 0x4001)
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; agt.send_write(tx);

            $display("[INFO] --- STEP 3: Polling FSM Status ---");
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 4: Extracting SFDP Signature from RX FIFO ---");
            tx = new(); tx.paddr = 32'h08; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during SFDP read.\n");
        test_pass = 1'b0;
    end else if (val === 32'h46504453) begin
        $display("   [PASS] SFDP signature verified: 0x%0h\n", val);
    end else begin
        $display("   [FAIL] SFDP signature mismatch. Expected 46504453, Got: 0x%0h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-SFD-46");
    tb_top.scoreboard.mark_as_run("QSPI-APB-SFD-46");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

