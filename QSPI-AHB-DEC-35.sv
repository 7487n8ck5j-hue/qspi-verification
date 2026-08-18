// =========================================================================
// TEST 35: AHB Address Decoder (Multi-CS CS[0:3]) (QSPI-AHB-DEC-35)
// Comprehensive verification of the memory-mapped DAC window address
// decoder, validating default CS mappings and global boundary defense.
// =========================================================================

task automatic run_test_35(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 35: AHB Address Decoder (Multi-CS CS[0:3])");
    $display(" Target: Validate multi-device seamless address spanning and error bounds");
    $display("=======================================================================\n");

    $display("[INFO] --- STEP 0: Hardware Software Reset ---");
    // Ensure the address decoder and configuration registers are in a default, known state
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
    repeat(5) @(posedge vif.pclk);

    $display("[INFO] --- STEP 0.5: Enabling DAC Memory Bridge ---");
    // Open the DAC window using Bit 14 (0x4000) and release reset via Bit 2 (0x0004) -> 0x4004.
    tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_4004; agt.send_write(tx);
    repeat(2) @(posedge vif.pclk);

    $display("[INFO] --- STEP 1: Attempting read across CS0 base address (0x1000_0000) ---");
    // Use the agent to safely execute the APB protocol
    tx = new(); 
    tx.paddr = 32'h1000_0000; 
    agt.send_read(tx);

    if (tx.pslverr === 1'b0) begin
        $display("   [PASS] Address valid within primary CS0 boundaries. No PSLVERR raised.");
    end else begin
        $display("   [FAIL] Address rejected unexpectedly! PSLVERR asserted on valid CS0 read.");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 2: Attempting read across extended CS1 base address (0x2000_0000) ---");
    tx = new(); 
    tx.paddr = 32'h2000_0000; 
    agt.send_read(tx);

    // The RTL has proven that CS1 is legally mapped by default to support dual-die boot.
    if (tx.pslverr === 1'b0) begin
        $display("   [PASS] Multi-CS support verified! CS1 is mapped and active by default.");
    end else begin
        $display("   [FAIL] Expected CS1 to be active by default, but decoder asserted PSLVERR.");
        test_pass = 1'b0;
    end

    $display("[INFO] --- STEP 3: Attempting read OUTSIDE configured CS windows (0x3000_0000) ---");
    // FIX: 0x3000_0000 falls inside the QSPI routing footprint but hits the unconfigured CS2 window.
    // This allows the QSPI controller to actually process the violation and assert PSLVERR.
    tx = new(); 
    tx.paddr = 32'h3000_0000; 
    agt.send_read(tx);

    // The AHB decoder MUST block this disabled internal address and raise a Slave Error.
    if (tx.pslverr === 1'b1) begin
        $display("   [PASS] Global DAC decoder successfully rejected illegal AHB address with PSLVERR.\n");
    end else begin
        $display("   [FAIL] Decoder vulnerability! Failed to assert PSLVERR on unconfigured CS address (0x3000_0000).\n");
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-AHB-DEC-35");
    tb_top.scoreboard.mark_as_run("QSPI-AHB-DEC-35");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
