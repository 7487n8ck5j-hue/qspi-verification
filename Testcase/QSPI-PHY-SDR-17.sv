// =========================================================================
// TEST 17: Data Learning Pattern (TDP) Training (QSPI-PHY-SDR-17)
// FIX: Replaced unstable local mock slave with the global flash model.
//      Corrected FSM busy bit polling from legacy Bit 11 to Bit 20.
// =========================================================================
task automatic run_test_17(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val; 
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 17: Data Learning Pattern (TDP) Training");
    $display(" Target: QSPI-PHY-SDR-17 | Training Pattern Extraction & Setup");
    $display("=======================================================================\n");

    // FIX: Utilize robust global flash model instead of local threads
    tb_top.flash_enable = 1'b1;
    tb_top.flash_quad_mode = 1'b0;
    // Shift out MSB first: '5A' will be captured in the first 8 clocks
    tb_top.flash.set_pattern(32'h5A5A_A5A5);
    // RX-Only mode means 0 clocks of TX/Dummy delay before data starts shifting
    tb_top.flash.set_delay(0);

    begin : master_apb_sequence
        $display("[INFO] --- STEP 0: Hardware Software Reset ---");
        // Flush the FIFOs to remove ghost data left over from previous tests
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; 
        agt.send_write(tx);
        repeat(5) @(posedge vif.pclk);

        $display("[INFO] --- STEP 1: Configuring QSPI Master Architecture ---");
        // Clock Divider to 4
        tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
        // Set Transfer Length to 7 (8 clock cycles total) to read exactly 1 byte
        tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; agt.send_write(tx);

        $display("[INFO] --- STEP 2: Triggering RX-Only Mode ---");
        // Trigger RX (Bits 14:13=00 [RX Mode], Bit 0=1 [Start] -> 0x0001)
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; agt.send_write(tx); 
        
        $display("[INFO] --- STEP 3: Actively Polling FSM Status ---");
        repeat(2) @(posedge vif.pclk);
        timeout_ctr = 0;
        do begin
            tx = new(); tx.paddr = 32'h18; 
            agt.send_read(tx);
            @(posedge vif.pclk); 
            timeout_ctr++;
        // FIX: Poll Bit 20 instead of legacy Bit 11
        end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);

        $display("   [DEBUG] FSM returned to IDLE after %0d APB clock cycles.", timeout_ctr);

        $display("[INFO] --- STEP 4: Extracting Payload from RX FIFO ---");
        // Read the captured byte from RX FIFO (0x08)
        tx = new(); tx.paddr = 32'h08; 
        agt.send_read(tx);
        val = tx.prdata;
    end

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] Hardware locked up during TDP training read.\n");
        test_pass = 1'b0;
    end else if (val === 32'h0000_005A) begin
        $display("   [PASS] Training Pattern correctly captured: %h\n", val);
    end else begin
        $display("   [FAIL] Clock phase slip detected! Expected 0000_005A, Got: %h\n", val);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-SDR-17");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-SDR-17");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
