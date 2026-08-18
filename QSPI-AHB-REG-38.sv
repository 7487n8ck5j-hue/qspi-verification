// =========================================================================
// TEST 38: AHB Address Remap / Decoder (QSPI-AHB-REG-38)
// Comprehensive verification of the APB address decoder, ensuring out-of-bounds
// register accesses are safely caught and rejected with a Slave Error (PSLVERR).
// =========================================================================

task automatic run_test_38(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    bit test_pass = 1'b1;
    
    $display("\n=======================================================================");
    $display(" TEST 38: AHB Address Remap / Decoder (QSPI-AHB-REG-38)");
    $display(" Target: Validate APB address bounds checking and error generation");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Attempting Out-of-Bounds APB Register Read ---");
    // Offset 0xFC is well outside the valid APB register map (typically 0x00 - 0x2C)
    // We expect the DUT's address decoder to block this and raise pslverr.
    tx = new();
    tx.paddr = 32'h0000_00FC; 
    
    $display("   [DEBUG] Sending out-of-bounds READ to APB address 0x%0h...", tx.paddr);
    agt.send_read(tx); 

    $display("[INFO] --- STEP 2: Evaluating Address Decoder Response ---");
    // The driver automatically captures the slave error and data into the transaction
    if (tx.pslverr === 1'b1) begin 
        $display("   [PASS] Hardware Translation safely rejected out-of-bounds map. (pslverr active).\n");
    end else begin 
        $display("   [FAIL] Translation logic failed to assert error on out-of-bounds access. Data returned: %h\n", tx.prdata);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-AHB-REG-38");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-REG-38");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
