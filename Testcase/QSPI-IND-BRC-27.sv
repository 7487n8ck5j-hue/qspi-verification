// =========================================================================
// TEST 27: INDAC Bulk Read Configuration (QSPI-IND-BRC-27)
// Comprehensive validation of queued sequential multi-byte reads, enforcing
// strict APB polling, correct CDC delays, and FIFO isolation.
// =========================================================================

task automatic run_test_27(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val;
    bit test_pass = 1'b1;
    int timeout_ctr = 0;

    $display("\n=======================================================================");
    $display(" TEST 27: INDAC Bulk Read Configuration");
    $display(" Target: QSPI-IND-BRC-27 | Validate sequential multi-byte INDAC reads");
    $display("=======================================================================\n");

    // We use fork..join_any to run the APB Master and a Custom Driving Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Custom Driving Mock Flash Slave (D1 high drive)
        // ---------------------------------------------------------
        begin : custom_driving_slave
            forever begin
                @(negedge vif.CS_n);
                #1; // Delta-cycle safety
                while (vif.CS_n == 1'b0) begin
                    @(negedge vif.CLK);
                    #1;
                    vif.D1 <= 1'b1; // Drive high continuously
                end
                #1;
                vif.D1 <= 1'bz; // Drive High-Z when CS_n is released
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master APB Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            // Flush the FIFOs to clear the garbage left by previous tests
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
            // FIX: Write length to 0x10 (XFERLEN_REG), NOT 0x14
            // 32 cycles = 0x1F transfer length per read operation
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); 

            $display("[INFO] --- STEP 2: Triggering Sequential Multi-Byte Reads ---");
            
            // Read Operation 1
            $display("   [DEBUG] Dispatching Read Request 1...");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; agt.send_write(tx); 
            
            // FIX: Proper CDC Delay & Polling Status Register (0x18) Bit 11
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; 
                agt.send_read(tx);
                @(posedge vif.pclk); 
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);

            // Read Operation 2
            $display("   [DEBUG] Dispatching Read Request 2...");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; agt.send_write(tx); 
            
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; 
                agt.send_read(tx);
                @(posedge vif.pclk); 
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);
        end
    join_any
    
    // Safety cleanup: Kill background slave and release pin immediately
    disable fork; 
    vif.D1 <= 1'bz; 

    $display("[INFO] --- STEP 3: Validating Queued Read Data ---");
    
    // Fetch Word 1 from RX FIFO (0x08)
    tx = new(); tx.paddr = 32'h08; 
    agt.send_read(tx);
    val = tx.prdata;
    
    if (val === 32'hFFFF_FFFF) begin
        $display("   [PASS] Word 1 accurately fetched expected payload: %h", val);
    end else begin
        $display("   [FAIL] Word 1 Mismatch: Expected FFFFFFFF, Got: %h", val);
        test_pass = 1'b0;
    end

    // Fetch Word 2 from RX FIFO (0x08)
    tx = new(); tx.paddr = 32'h08; 
    agt.send_read(tx);
    val = tx.prdata;
    
    if (val === 32'hFFFF_FFFF) begin
        $display("   [PASS] Word 2 accurately fetched expected payload: %h\n", val);
    end else begin
        $display("   [FAIL] Word 2 Mismatch: Expected FFFFFFFF, Got: %h\n", val);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-IND-BRC-27");
    tb_top.scoreboard.mark_as_run("QSPI-IND-BRC-27");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
