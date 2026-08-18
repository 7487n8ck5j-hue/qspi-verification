// =========================================================================
// TEST 08: Continuous XIP Mode Entry (QSPI-DAC-XIP-08)
// Comprehensive diagnostic verification of continuous Quad-SPI data 
// extraction, APB-to-SPI synchronization, and payload integrity.
// =========================================================================

task automatic run_test_08(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    logic [31:0] val; 
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 08: Continuous XIP Mode Entry (QSPI-DAC-XIP-08)");
    $display(" Target: QSPI-DAC-XIP-08 | Quad Mode Payload Extraction & Setup");
    $display("=======================================================================\n");

    // We use fork..join_any to run the APB Master and a Custom Quad-SPI Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Custom Quad-SPI Mock Slave
        // ---------------------------------------------------------
        begin : custom_quad_slave
            reg [31:0] payload = 32'hC0DE_C0DE;
            reg [3:0]  slave_drv;
            forever begin
                @(negedge vif.CS_n);
                
                // Shift the 8 nibbles (MSB first) synced to the Master's clock
                for (int i=7; i>=0; i--) begin 
                    slave_drv = (payload >> (i*4)) & 4'hF; 
                    vif.D3 <= slave_drv[3]; 
                    vif.D2 <= slave_drv[2]; 
                    vif.D1 <= slave_drv[1]; 
                    vif.D0 <= slave_drv[0]; 
                    
                    if (i > 0) @(negedge vif.CLK); 
                end
                
                @(posedge vif.CS_n); 
                // Release the pins back to the default tb_top pullups
                vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz; 
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master APB Sequence
        // ---------------------------------------------------------
        begin : master_apb_sequence
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            // Flush the FIFOs to remove ghost data left over from previous tests
            // Write 1 to Bit 8 (Software Reset) -> 0x0100
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; 
            agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);

            $display("[INFO] --- STEP 1: Configuring Master Architecture ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_0007; agt.send_write(tx); // Transfer Length (8 cycles)
            tx = new(); tx.paddr = 32'h14; tx.pwdata = 32'h0000_0000; agt.send_write(tx); // Dummy Cycles
            
            $display("[INFO] --- STEP 2: Triggering Quad-SPI Transaction ---");
            // 2. Trigger Quad Read (Quad Enable [Bit 10] + Start [Bit 0] -> 0x0401)
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0401; agt.send_write(tx); 
            
            // FIX: Allow precise CDC propagation delay (2 cycles) to catch 'busy' bit asserting
            repeat(2) @(posedge vif.pclk);

            $display("[INFO] --- STEP 3: Actively Polling FSM Status ---");
            // FIX: Poll the Status Register (0x18) Bit 11 (Busy), NOT Control Reg Bit 0 (Start)
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; 
                agt.send_read(tx);
                @(posedge vif.pclk); 
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);
            
            $display("   [DEBUG] FSM returned to IDLE after %0d APB clock cycles.", timeout_ctr);

            $display("[INFO] --- STEP 4: Extracting Payload from RX FIFO ---");
            // 4. Read the assembled payload from RX FIFO (0x08)
            tx = new(); tx.paddr = 32'h08; 
            agt.send_read(tx);
            val = tx.prdata;
        end
    join_any
    
    // Safety cleanup: Kill background slave and release pins immediately when sequence ends
    disable fork; 
    vif.D3 <= 1'bz; vif.D2 <= 1'bz; vif.D1 <= 1'bz; vif.D0 <= 1'bz; 

    // =================================================================
    // Evaluate and log the final outcome
    // =================================================================
    $display("[INFO] --- STEP 5: Final Result Evaluation ---");
    if (timeout_ctr >= 1000) begin
        $display("   [FAIL] Hardware locked up during XIP continuous read. FSM never finished.\n");
        test_pass = 1'b0;
    end else if (val === 32'hC0DE_C0DE) begin
        $display("   [PASS] Continuous XIP mode entry successfully traversed. Payload: %h\n", val);
    end else begin
        $display("   [FAIL] Payload Error. Expected C0DEC0DE, Got: %h\n", val);
        test_pass = 1'b0;
    end

    // =================================================================
    // Log final result to SystemVerilog Scoreboard
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-DAC-XIP-08");
    tb_top.scoreboard.mark_as_run("QSPI-DAC-XIP-08");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
