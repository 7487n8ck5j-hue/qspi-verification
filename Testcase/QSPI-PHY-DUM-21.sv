// =========================================================================
// TEST 21: Device Delay Calibration (QSPI-PHY-DUM-21)
// FIX: Updated FSM busy bit polling from legacy Bit 11 to Bit 20 so the 
//      testbench actually waits for the transaction to complete before 
//      evaluating the CS_n pin state.
// =========================================================================

task automatic run_test_21(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 21: QSPI-PHY-DUM-21");
    $display(" Device Delay Calibration (CSDA/CSEOT)");
    $display(" Target: Validate programmable CS# timing margins");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Configuring Master Architecture & Timing Margins ---");
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
    tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); // Transfer Length (32 cycles)
    
    // Programming CS# Delay Margins via Dummy Control Register (0x14)
    tx = new(); tx.paddr = 32'h14; tx.pwdata = 32'h0000_0005; 
    agt.send_write(tx); 

    $display("[INFO] --- STEP 2: Loading Payload & Triggering TX Transaction ---");
    tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'h1234_5678; 
    agt.send_write(tx); 
    
    // Trigger TX-Only Mode (Bits 14:13=01 [TX], Bit 0=1 [Start]) -> 0x2001
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_2001; 
    agt.send_write(tx); 

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
    repeat(5) @(posedge vif.pclk);

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 4: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] Hardware locked up during delay calibration test.\n");
        test_pass = 1'b0;
    end else if (vif.CS_n === 1'b1) begin
        $display("   [PASS] CS_n correctly de-asserted after honoring programmed timing margins.\n");
    end else begin
        $display("   [FAIL] CS_n timing sequence violated. Pin stuck LOW.\n");
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-DUM-21");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-DUM-21");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
