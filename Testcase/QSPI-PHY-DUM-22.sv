// =========================================================================
// TEST 22: Dummy Clock Cycle Generation (Quad Mode) (QSPI-PHY-DUM-22)
// FIX: Replaced unstable local mock slave with the global flash model.
//      Set flash delay to 6 to properly simulate the 6 dummy wait states 
//      before data begins driving on the Quad lines.
// =========================================================================

task automatic run_test_22(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val; 
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 22: Dummy Clock Cycle Generation (Quad Mode)");
    $display(" Target: QSPI-PHY-DUM-22 | Validate programmable dummy wait states");
    $display("=======================================================================\n");

    // FIX: Utilize robust global flash model instead of local threads
    tb_top.flash_enable = 1'b1;
    tb_top.flash_quad_mode = 1'b1;
    tb_top.flash.set_pattern(32'hDEAD_BEEF);
    
    // RX-Only mode with 6 dummy cycles programmed in Master
    tb_top.flash.set_delay(6);

    begin : master_apb_sequence
        $display("[INFO] --- STEP 0: Hardware Software Reset ---");
        // Flush the FIFOs to remove ghost data left over from previous tests
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
        repeat(5) @(posedge vif.pclk);

        $display("[INFO] --- STEP 1: Configuring QSPI Master Architecture ---");
        tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
        tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; agt.send_write(tx); // Transfer Length (8 cycles)

        $display("[INFO] --- STEP 2: Program Dummy Cycles and Trigger RX ---");
        tx = new(); tx.paddr = 32'h14; tx.pwdata = 32'h0000_0006; agt.send_write(tx); // Program 6 Dummy Cycles
        
        // Trigger Quad Mode (Bits 14:13=00 [RX], Bit 10=1 [Quad], Bit 0=1 [Start]) -> 0x0401
        tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0401; agt.send_write(tx); 
        
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
        // Read the fetched payload from RX FIFO (0x08)
        tx = new(); tx.paddr = 32'h08; 
        agt.send_read(tx);
        val = tx.prdata;
    end
    
    // Safety cleanup
    tb_top.flash_quad_mode = 1'b0;

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] Hardware locked up during dummy cycle test.\n");
        test_pass = 1'b0;
    end else if (val === 32'hDEAD_BEEF) begin
        $display("   [PASS] Data correctly fetched after 6 wait states. Payload: %h\n", val);
    end else begin
        $display("   [FAIL] Expected DEADBEEF, Got: %h\n", val);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-PHY-DUM-22");
    tb_top.scoreboard.mark_as_run("QSPI-PHY-DUM-22");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
