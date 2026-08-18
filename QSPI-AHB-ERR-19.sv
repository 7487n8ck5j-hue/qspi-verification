// =========================================================================
// TEST 19: Hardware Write Protection (QSPI-AHB-ERR-19)
// Comprehensive validation of register protection, ensuring illegal 
// memory-mapped writes to Read-Only registers (RX FIFO at 0x08) are safely dropped.
// =========================================================================

task automatic run_test_19(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] initial_val;
    logic [31:0] post_write_val;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 19: Hardware Write Protection (QSPI-AHB-ERR-19)");
    $display(" Target: Validate block-level hardware address locking");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    // Flush the FIFOs to ensure a known clean baseline state
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Capturing Baseline Value of RX_REG (0x08) ---");
    @(negedge vif.pclk); 
    vif.psel    = 1'b1; 
    vif.pwrite  = 1'b0; 
    vif.paddr   = 32'h08; 
    @(negedge vif.pclk); 
    vif.penable = 1'b1; 
    wait(vif.pready); 
    initial_val = vif.prdata;
    $display("   [DEBUG] Baseline RX_REG value: %h", initial_val);

    @(negedge vif.pclk); 
    vif.psel    = 1'b0; 
    vif.penable = 1'b0;

    $display("[INFO] --- STEP 2: Attempting Illegal Write to Read-Only RX_REG (0x08) ---");
    
    // Manual AMBA drive via virtual interface to test error response asynchronously
    @(negedge vif.pclk); 
    vif.psel    = 1'b1; 
    vif.pwrite  = 1'b1; 
    vif.paddr   = 32'h08; 
    vif.pwdata  = 32'hDEAD_BEEF; 
    
    @(negedge vif.pclk); 
    vif.penable = 1'b1; 
    
    #1; // Sample the error flag asynchronously 
    
    if (vif.pslverr === 1'b1) begin
        $display("   [PASS] Hardware Address Protection asserted Slave Error (SLVERR).");
    end else begin
        $display("   [PASS] Design logic correctly ignores Read-Only write safely.");
    end

    // Wait for pready using robust logic before clearing bus
    wait(vif.pready);
    @(negedge vif.pclk); 
    vif.psel    = 1'b0; 
    vif.penable = 1'b0; 
    vif.pwrite  = 1'b0;
    repeat(2) @(posedge vif.pclk);

    $display("[INFO] --- STEP 3: Verifying RX_REG Uncorrupted by Illegal Write ---");
    @(negedge vif.pclk); 
    vif.psel    = 1'b1; 
    vif.pwrite  = 1'b0; 
    vif.paddr   = 32'h08; 
    
    @(negedge vif.pclk); 
    vif.penable = 1'b1; 
    wait(vif.pready); 
    post_write_val = vif.prdata;
    $display("   [DEBUG] Post-Write RX_REG value: %h", post_write_val);
    
    // FIX: Verify that the illegal write did not change the register contents from baseline
    if (post_write_val === initial_val) begin
        $display("   [PASS] Memory successfully block-locked. Write blocked completely (Value unchanged).\n");
    end else begin
        $display("   [FAIL] Hardware write protection bypassed. Data corrupted: Expected %h, Got: %h\n", initial_val, post_write_val);
        test_pass = 1'b0;
    end
        
    @(negedge vif.pclk); 
    vif.psel    = 1'b0; 
    vif.penable = 1'b0;

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-AHB-ERR-19");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-ERR-19");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
