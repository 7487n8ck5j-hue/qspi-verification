// =========================================================================
// TEST 01: Boot Payload Validation (QSPI-AHB-SDR-01)
// FIX: Set rx_delay to 0. CTRL register is programmed with 0x0005 (Mode 00), 
//      which is RX-ONLY mode. There is no TX phase, so the flash model 
//      must drive data immediately from cycle 0.
// =========================================================================
task automatic run_test_01(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    int timeout_ctr = 0;
    int cs_toggles = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 01: Boot Payload Validation (QSPI-AHB-SDR-01)");
    $display("=======================================================================\n");

    tb_top.flash_enable    = 1'b1;
    tb_top.flash_quad_mode = 1'b0;
    tb_top.flash.set_pattern(32'hB0B0_B0B0);
    
    // FIX: RX-ONLY Mode means 0 cycles of TX delay
    tb_top.flash.set_delay(0); 

    repeat(5) @(posedge vif.pclk);

    fork
        begin : cs_monitor
            forever begin
                @(negedge vif.CS_n);
                cs_toggles++;
            end
        end

        begin : test_sequence
            $display("[INFO] Step 1: Configuring QSPI Master Architecture & Flash Model...");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx);
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx);

            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h0300_0000; tx.pstrb = 4'hF; agt.send_write(tx);

            $display("[INFO] Step 2: Triggering SPI Transaction...");
            // Mode 2'b00 (RX ONLY) + START
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0005; tx.pstrb = 4'hF; agt.send_write(tx);

            repeat(2) @(posedge vif.pclk);
            $display("[INFO] Step 3: Waiting for FSM to complete...");
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; agt.send_read(tx);
                @(posedge vif.pclk);
                timeout_ctr++;
            end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

            if (timeout_ctr >= 1000) begin
                $display("   [FAIL] Hardware locked up.");
                test_pass = 1'b0;
            end

            $display("[INFO] Step 4: Reading fetched payload from RX FIFO...");
            tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; agt.send_read(tx);
            val = tx.prdata;
        end
    join_any

    disable fork;

    if (val === 32'h0000_00B0) begin
        $display("   [PASS] Boot Payload Validated: %h\n", val);
    end else begin
        $display("   [FAIL] Expected 0000_00B0, Got: %h\n", val);
        test_pass = 1'b0;
    end

    tb_top.scoreboard.set_current_test("QSPI-AHB-SDR-01");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-SDR-01");
    if (test_pass) tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    else tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
endtask
