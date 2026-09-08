// =========================================================================
// TEST 08: Continuous XIP Mode Entry (QSPI-DAC-XIP-08) — CORRECTED
// FIX: Add second read without re-sending opcode (true XIP continuous read)
// =========================================================================
task automatic run_test_08(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val1, val2;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 08: Continuous XIP Mode Entry (QSPI-DAC-XIP-08)");
    $display("=======================================================================\n");

    fork
        begin : mock_xip_slave
            reg [31:0] payload1 = 32'hAAAA_1111;
            reg [31:0] payload2 = 32'hBBBB_2222;
            int read_count = 0;
            forever begin
                @(negedge vif.CS_n);
                #1;
                // First read: send opcode + address + dummy + data
                // Second read (XIP): just data, no opcode
                for (int i=31; i>=0; i--) begin
                    if (read_count == 0)
                        vif.D1 <= payload1[i];
                    else
                        vif.D1 <= payload2[i];
                    if (i > 0) @(negedge vif.CLK);
                end
                read_count++;
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

            // --- First read: with opcode ---
            $display("[INFO] --- STEP 2: First Read (with opcode 0x03) ---");
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
            val1 = tx.prdata;
            $display("   [DEBUG] First read: 0x%0h", val1);

            // FIX: Second read WITHOUT re-sending opcode (true XIP continuous read)
            $display("[INFO] --- STEP 3: Second Read (XIP — no opcode) ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
            val2 = tx.prdata;
            $display("   [DEBUG] Second read (XIP): 0x%0h", val2);
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up.\n");
        test_pass = 1'b0;
    end else if (val1 === 32'hAAAA_1111 && val2 === 32'hBBBB_2222) begin
        $display("   [PASS] XIP continuous read verified. Read1: %h, Read2: %h\n", val1, val2);
    end else begin
        $display("   [FAIL] XIP read mismatch. Read1: %h (exp AAAA1111), Read2: %h (exp BBBB2222)\n", val1, val2);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-DAC-XIP-08");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-XIP-08");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

