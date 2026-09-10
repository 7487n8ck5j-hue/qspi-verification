// =========================================================================
// TEST 15: Read Data Capturing via Internal Taps (QSPI-PHY-SDR-15)
// FIX: Replaced unstable local mock slave with the global flash model.
//      Corrected FSM busy bit polling from legacy Bit 11 to Bit 20.
// =========================================================================
task automatic run_test_15(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val; 
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 15: QSPI-PHY-SDR-15");
    $display(" Read Data Capturing via Internal Taps");
    $display(" Validate data sampling bypassing the PHY Module.");
    $display("=======================================================================\n");

    // FIX: Utilize robust global flash model instead of local threads
    tb_top.flash_enable = 1'b1;
    tb_top.flash_quad_mode = 1'b0;
    // Shift out MSB first: 'FE' will be captured in the first 8 clocks
    tb_top.flash.set_pattern(32'hFEED_BACC);
    // RX-Only mode means 0 clocks of TX/Dummy delay before data starts shifting
    tb_top.flash.set_delay(0);

    begin : master_apb_sequence
        $display("[INFO] --- STEP 0: Hardware Software Reset ---");
        // Flush the FIFOs to remove ghost data left over from previous tests
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; tx.pstrb = 4'hF; 
        agt.send_write(tx);
        repeat(5) @(posedge vif.pclk);

        $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
        // Clock Divider to 4
        tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; tx.pstrb = 4'hF; agt.send_write(tx); 
        // Set Transfer Length to 7 (8 clock cycles total) to read exactly 1 byte
        tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; tx.pstrb = 4'hF; agt.send_write(tx); 
        
        $display("[INFO] --- STEP 2: Triggering RX-Only Mode ---");
        // Trigger RX (Bits 14:13=00 [RX Mode], Bit 0=1 [Start] -> 0x0001)
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; tx.pstrb = 4'hF; agt.send_write(tx); 
        
        $display("[INFO] --- STEP 3: Actively Polling FSM Status ---");
        repeat(2) @(posedge vif.pclk);
        timeout_ctr = 0;
        do begin
            tx = new(); tx.paddr = 32'h18; tx.pstrb = 4'hF; 
            agt.send_read(tx);
            @(posedge vif.pclk); 
            timeout_ctr++;
        // FIX: Poll Bit 20 instead of legacy Bit 11
        end while (tx.prdata[20] == 1'b1 && timeout_ctr < 1000);
        
        $display("   [DEBUG] FSM returned to IDLE after %0d APB clock cycles.", timeout_ctr);

        $display("[INFO] --- STEP 4: Extracting Payload from RX FIFO ---");
        // Read the captured byte from RX FIFO (0x08)
        tx = new(); tx.paddr = 32'h08; tx.pstrb = 4'hF; 
        agt.send_read(tx);
        val = tx.prdata;
    end

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] Hardware locked up during internal tap read.\n");
        test_pass = 1'b0;
    end else if (val === 32'h0000_00FE) begin
        $display("   [PASS] Internal tap data captured successfully: %h\n", val);
    end else begin
        $display("   [FAIL] Expected 0000_00FE, Got: %h\n", val);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-SDR-15");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-SDR-15");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
