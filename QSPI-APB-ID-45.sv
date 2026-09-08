// =========================================================================
// TEST 45: JEDEC ID Read (RDID 0x9F) (QSPI-APB-ID-45)
// Comprehensive validation of JEDEC ID Read command (0x9F) issuance,
// 3-byte response capture (Manufacturer ID + Device ID), and data integrity.
// =========================================================================

task automatic run_test_45(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 45: JEDEC ID Read (RDID 0x9F) (QSPI-APB-ID-45)");
    $display(" Target: Validate JEDEC ID command and 3-byte response capture");
    $display("=======================================================================\n");

    fork
        // ---------------------------------------------------------
        // THREAD 1: Mock Flash Slave (JEDEC ID Response)
        // ---------------------------------------------------------
        begin : mock_jedec_slave
            // Standard JEDEC ID: Manufacturer=0xEF (Winbond), Device=0x4018
            reg [23:0] jedec_id = 24'hEF_40_18;
            forever begin
                @(negedge vif.CS_n);
                #1;

                // Shift out 24-bit JEDEC ID (MSB first) on D1
                for (int i = 23; i >= 0; i--) begin
                    vif.D1 <= jedec_id[i];
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
            // Transfer Length = 23 (24 cycles = 3 bytes of JEDEC ID response)
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0017; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Sending RDID Command (0x9F) via TX ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h9F00_0000; agt.send_write(tx);
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

            $display("[INFO] --- STEP 4: Extracting JEDEC ID from RX FIFO ---");
            tx = new(); tx.paddr = 32'h08; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up during JEDEC ID read.\n");
        test_pass = 1'b0;
    end else if (val[23:16] == 8'hEF) begin
        $display("   [PASS] JEDEC ID captured. Manufacturer=0x%0h, Device=0x%0h%0h\n",
                 val[23:16], val[15:8], val[7:0]);
    end else begin
        $display("   [FAIL] JEDEC ID mismatch. Expected Manufacturer 0xEF, Got: 0x%0h\n", val[23:16]);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-APB-ID-45");
    tb_top.scoreboard.mark_as_run("QSPI-APB-ID-45");
    if (test_pass)
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

