// =========================================================================
// TEST 05: QSPI XIP Boot Instruction Fetch (QSPI-DAC-XIP-05) — CORRECTED
// FIX: Remove hallucinated bit 14 (DAC Enable). Use valid Quad RX mode (0x0401).
// =========================================================================
task automatic run_test_05(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 05: QSPI XIP Boot Instruction Fetch (QSPI-DAC-XIP-05)");
    $display("=======================================================================\n");

    fork
        begin : custom_quad_slave
            reg [31:0] payload = 32'h1A57_8C73;
            reg [3:0]  slave_drv;
            forever begin
                @(negedge vif.CS_n);
                repeat(6) @(negedge vif.CLK);
                #1;
                for (int i=7; i>=0; i--) begin
                    slave_drv = (payload >> (i*4)) & 4'hF;
                    vif.D3 <= slave_drv[3]; vif.D2 <= slave_drv[2];
                    vif.D1 <= slave_drv[1]; vif.D0 <= slave_drv[0];
                    if (i > 0) @(negedge vif.CLK);
                end
                @(posedge vif.CS_n);
                #1;
                vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz;
            end
        end

        begin : master_apb_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; tx.pstrb = 4'hF; agt.send_write(tx);

            $display("[INFO] --- STEP 2: Triggering Quad RX Mode ---");
            // FIX: Use valid Quad RX mode (Bit 10 + Bit 0 = 0x0401) instead of hallucinated bit 14
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0401; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            $display("[INFO] --- STEP 3: Reading Payload from RX FIFO ---");
            tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;
    vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz;

    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] FSM locked up.\n");
        test_pass = 1'b0;
    end else if (val === 32'h1A57_8C73) begin
        $display("   [PASS] Quad Boot Payload Fetched: %h\n", val);
    end else begin
        $display("   [FAIL] Expected 1A578C73, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-DAC-XIP-05");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-XIP-05");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask

