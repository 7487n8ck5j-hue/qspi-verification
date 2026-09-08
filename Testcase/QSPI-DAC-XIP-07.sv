// =========================================================================
// TEST 07: SPI Standard Read Alignment (QSPI-DAC-XIP-07) — CORRECTED
// FIX: Add Mode Bit configuration testing + use exact pass criteria
// =========================================================================
task automatic run_test_07(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 07: SPI Standard Read Alignment (QSPI-DAC-XIP-07)");
    $display("=======================================================================\n");

    fork
        begin : mock_slave
            reg [31:0] payload = 32'hDEAD_BEEF;
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
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; tx.pstrb = 4'hF; agt.send_write(tx);

            // FIX: Add Mode Bit configuration (Dummy Cycles register 0x14)
            $display("[INFO] --- STEP 2: Configuring Mode Bits (Dummy Cycles = 8) ---");
            tx = new(); tx.paddr = 32'h14; tx.pwdata = 32'h0000_0008; tx.pstrb = 4'hF; agt.send_write(tx);

            $display("[INFO] --- STEP 3: Sending Standard Read Opcode (0x03) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 4: Reading Payload from RX FIFO ---");
            tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    // FIX: Exact match instead of "not 0xFF and not 0x00"
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up.\n");
        test_pass = 1'b0;
    end else if (val === 32'hDEAD_BEEF) begin
        $display("   [PASS] Standard Read data captured: %h\n", val);
    end else begin
        $display("   [FAIL] Expected DEADBEEF, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-DAC-XIP-07");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-XIP-07");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

