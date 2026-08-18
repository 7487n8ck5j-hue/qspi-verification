// =========================================================================
// TEST 39: SRAM Overrun / Back-Pressure Handling (QSPI-IND-LVL-39)
// Comprehensive verification of FIFO overrun protection, proving the hardware
// throttles data at maximum capacity using Split-Register APB polling.
// =========================================================================

task automatic run_test_39(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [3:0] fifo_cnt;
    logic       tx_full_flag;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 39: SRAM Overrun / Back-Pressure Handling (QSPI-IND-LVL-39)");
    $display(" Target: Validate hardware queue throttling and TX_FULL flag assertion");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    // Flush previous states to guarantee an absolutely empty FIFO baseline
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Waking Up Internal Clock Domain ---");
    // Configure the clock divider (0x0C) to un-gate the internal SPI clock 
    // so the async FIFO synchronizers can evaluate the boundary flags.
    tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx);
    repeat(2) @(posedge vif.pclk);

    $display("[INFO] --- STEP 2: Pushing 10 words into the 8-word TX FIFO ---");
    // Intentionally overload the queue by writing to TX Register (0x04)
    for (int i = 0; i < 10; i++) begin
        tx = new(); 
        tx.paddr = 32'h04; 
        tx.pwdata = 32'hA1A1_A1A1; 
        agt.send_write(tx);
    end

    // Allow the async FIFO gray-code pointers to synchronize across clock domains
    repeat(10) @(posedge vif.pclk);

    $display("[INFO] --- STEP 3: Validating Split-Register Hardware Back-Pressure ---");
    
    // 1. Read the Diagnostic Status Register (0x18) for the physical count
    tx = new(); tx.paddr = 32'h18; agt.send_read(tx);
    fifo_cnt = tx.prdata[3:0];
    
    // 2. Read the Control/Interrupt Register (0x00) for the TX_FULL flag
    tx = new(); tx.paddr = 32'h00; agt.send_read(tx);
    tx_full_flag = tx.prdata[5];
    
    $display("   [DEBUG] Diagnostic Reg (0x18) TX_FIFO_CNT : %0d", fifo_cnt);
    $display("   [DEBUG] Control Reg (0x00) TX_FIFO_FULL   : %b", tx_full_flag);

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 4: Final Result Evaluation ---");
    if (fifo_cnt == 4'd8 && tx_full_flag === 1'b1) begin
        $display("   [PASS] Hardware throttled queue perfectly at 8 words. TX_FULL flag successfully asserted.\n");
    end else begin
        $display("   [FAIL] Hardware failed to clamp queue size! (Count: %0d, TX_Full: %b)\n", fifo_cnt, tx_full_flag);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-IND-LVL-39");
    tb_top.scoreboard.mark_as_run("QSPI-IND-LVL-39");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
