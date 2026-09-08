// =========================================================================
// TEST 43: Page Program Sequence (QSPI-SPI-PGM-43) — CORRECTED
// FIX 1: Line 32 "vif.vif.CLK" → "vif.CLK" (MFNF error)
// FIX 2: Add tx.pstrb = 4'hF to all APB transactions
// =========================================================================
task automatic run_test_43(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    int poll_count = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 43: Page Program Sequence (QSPI-SPI-PGM-43)");
    $display(" Target: Validate WREN + Page Program + WIP polling");
    $display("=======================================================================\n");

    fork
        begin : mock_program_slave
            int pgm_poll_count = 0;
            reg [7:0] cmd_byte;
            forever begin
                @(negedge vif.CS_n);
                #1;
                cmd_byte = 8'h00;
                for (int i = 7; i >= 0; i--) begin
                    @(posedge vif.CLK);  // FIX: was vif.vif.CLK
                    cmd_byte[i] = (vif.D0 === 1'bz) ? 1'b0 : vif.D0;
                end
                if (cmd_byte == 8'h05) begin
                    for (int i = 7; i >= 0; i--) begin
                        @(negedge vif.CLK);
                        #1;
                        if (i == 0)
                            vif.D1 <= (pgm_poll_count < 2) ? 1'b1 : 1'b0;
                        else
                            vif.D1 <= 1'b0;
                    end
                    pgm_poll_count++;
                end
                @(posedge vif.CS_n);
                #1;
                vif.D1 <= 1'bz;
            end
        end

        begin : master_apb_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Sending WREN (0x06) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0600_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 3: Sending Page Program (0x02) ---");
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0200_0000; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 4: Polling WIP via RDSR ---");
            val = 32'h0000_0001;
            poll_count = 0;
            while (val[0] == 1'b1 && poll_count < 50) begin
                tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0500_0000; tx.pstrb = 4'hF; agt.send_write(tx);
                tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; tx.pstrb = 4'hF; agt.send_write(tx);

                repeat(2) @(posedge vif.pclk);
                timeout_ctr = 0;
                do begin
                    tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                    @(posedge vif.pclk);
                    timeout_ctr++;
                end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

                tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
                val = tx.prdata;
                $display("   [DEBUG] RDSR Poll %0d: Status = %h (WIP = %b)", poll_count, val, val[0]);
                poll_count++;
            end
        end
    join_any

    disable fork;
    vif.D1 <= 1'bz;

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up.\n");
        test_pass = 1'b0;
    end else if (val[0] == 1'b0 && poll_count > 0 && poll_count < 50) begin
        $display("   [PASS] Page program completed. WIP cleared after %0d polls.\n", poll_count);
    end else begin
        $display("   [FAIL] Program polling failed. Final: %h, polls: %0d\n", val, poll_count);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-SPI-PGM-43");
    tb_top.scoreboard.mark_as_run("QSPI-SPI-PGM-43");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

