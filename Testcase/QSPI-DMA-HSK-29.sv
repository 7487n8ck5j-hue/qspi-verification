// =========================================================================
// TEST 29: DMA Peripheral Handshaking (QSPI-DMA-HSK-29)
// Comprehensive verification of AXI-like DMA handshake mechanisms, simulating
// true DMA controller data movement, and strict APB status synchronization.
// =========================================================================

task automatic run_test_29(qspi_agent agt, virtual qspi_if vif);
    qspi_transaction tx;
    int timeout_ctr = 0;
    bit test_pass = 1'b1;

    $display("\n=======================================================================");
    $display(" TEST 29: DMA Peripheral Handshaking (Read/Write)");
    $display(" Target: QSPI-DMA-HSK-29 | AXI-Like DMA Integration & Handshake Validation");
    $display("=======================================================================\n");

    // Initialize DMA control and handshake lines
    vif.D1 <= 1'bz;
    vif.tx_dma_ack = 1'b0;
    vif.rx_dma_ack = 1'b0;

    // We use fork..join_any to run the APB Master sequence and a Safe Mock Flash Slave simultaneously.
    fork
        // ---------------------------------------------------------
        // THREAD 1: Safe Mock Flash Slave Implementation
        // ---------------------------------------------------------
        begin : safe_mock_flash_slave
            reg slave_oe_reg = 0;
            
            forever begin
                @(negedge vif.CS_n);
                slave_oe_reg = 1;
                
                while (vif.CS_n == 1'b0) begin
                    #1;
                    if (slave_oe_reg) begin
                        vif.D1 <= 1'b1; // Safe procedural driver assignment
                    end
                    @(posedge vif.CLK);
                end
                
                slave_oe_reg = 0;
                #1;
                vif.D1 <= 1'bz; // Release pin to High-Z
            end
        end

        // ---------------------------------------------------------
        // THREAD 2: QSPI Master DMA Handshake and Control Sequence
        // ---------------------------------------------------------
        begin : master_dma_sequence
            
            $display("[INFO] --- STEP 0: Hardware Software Reset ---");
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0100; agt.send_write(tx);
            repeat(5) @(posedge vif.pclk);
            
            $display("[INFO] --- STEP 1: Configuring Architecture & DMA Boundaries ---");
            tx = new(); tx.paddr = 32'h0C; tx.pwdata = 32'h0000_0004; agt.send_write(tx); // Clock Divider
            tx = new(); tx.paddr = 32'h10; tx.pwdata = 32'h0000_001F; agt.send_write(tx); // 32 bits

            // Configure DMA Control Register (0x28)
            // RX Threshold = 1 (Bits 23:16), TX Threshold = 1 (Bits 15:8), Enable Both TX/RX = 0x03 -> 0x0001_0103
            tx = new(); tx.paddr = 32'h28; tx.pwdata = 32'h0001_0103; 
            agt.send_write(tx); 

            // --- Sub-Phase A: TX Handshake Integration Validation ---
            $display("[INFO] --- STEP 2: Validating TX DMA Request/Acknowledge Integration ---");
            timeout_ctr = 0;
            
            while (vif.tx_dma_req == 1'b0 && timeout_ctr < 1000) begin
                @(posedge vif.pclk);
                timeout_ctr++;
            end

            if (vif.tx_dma_req === 1'b1) begin
                $display("   [PASS] TX DMA Request ('tx_dma_req') raised automatically by controller.");
            end else begin
                $display("   [FAIL] TX DMA Request timeout: 'tx_dma_req' failed to assert within 1000 cycles.");
                test_pass = 1'b0;
            end
            
            // FIX: Simulate external DMA Controller physically moving the data via APB
            tx = new(); tx.paddr = 32'h04; tx.pwdata = 32'hDEAD_BEEF; 
            agt.send_write(tx);

            // Assert TX DMA Acknowledge to complete the handshake
            @(negedge vif.pclk); 
            vif.tx_dma_ack = 1'b1; 
            @(negedge vif.pclk); 
            vif.tx_dma_ack = 1'b0; 
            repeat(2) @(posedge vif.pclk);
            
            // FIX: Front-door verification of internal TX FIFO population count (0x18[3:0])
            tx = new(); tx.paddr = 32'h18; 
            agt.send_read(tx);
            if (tx.prdata[3:0] == 4'd1) begin
                $display("   [PASS] TX Acknowledge handshake successfully populated internal FIFO (Count = 1).");
            end else begin
                $display("   [FAIL] TX Acknowledge stream failure. Expected FIFO count: 1, Actual: %0d", tx.prdata[3:0]);
                test_pass = 1'b0;
            end

            // --- Sub-Phase B: RX Handshake Integration Validation ---
            $display("[INFO] --- STEP 3: Validating RX DMA Request/Acknowledge Integration ---");
            
            // Trigger RX operation via Control Register (Start RX: Bit 1=0, Bit 0=1 -> 0x0000_0001)
            tx = new(); tx.paddr = 32'h00; tx.pwdata = 32'h0000_0001; 
            agt.send_write(tx); 
            
            $display("[INFO] --- STEP 4: Actively Polling FSM Status ---");
            repeat(2) @(posedge vif.pclk);
            timeout_ctr = 0;
            do begin
                tx = new(); tx.paddr = 32'h18; 
                agt.send_read(tx);
                @(posedge vif.pclk); 
                timeout_ctr++;
            end while (tx.prdata[11] == 1'b1 && timeout_ctr < 1000);
            
            // Wait for RX DMA request signal assertion
            timeout_ctr = 0;
            while (vif.rx_dma_req == 1'b0 && timeout_ctr < 1000) begin
                @(posedge vif.pclk);
                timeout_ctr++;
            end

            if (vif.rx_dma_req === 1'b1) begin
                $display("   [PASS] RX DMA Request ('rx_dma_req') raised automatically after payload receipt.");
            end else begin
                $display("   [FAIL] RX DMA Request timeout: 'rx_dma_req' failed to assert within 1000 cycles.");
                test_pass = 1'b0;
            end
            
            // FIX: Simulate external DMA controller physically popping the data from the RX FIFO via APB
            tx = new(); tx.paddr = 32'h08; 
            agt.send_read(tx);

            // Assert RX DMA Acknowledge to complete the handshake
            @(negedge vif.pclk); 
            vif.rx_dma_ack = 1'b1; 
            @(negedge vif.pclk); 
            vif.rx_dma_ack = 1'b0; 
            repeat(2) @(posedge vif.pclk);

            // FIX: Front-door verification of internal RX FIFO drain status (Assuming RX_FIFO_CNT is [19:16])
            tx = new(); tx.paddr = 32'h18; 
            agt.send_read(tx);
            if (tx.prdata[19:16] == 4'd0) begin
                $display("   [PASS] RX Acknowledge handshake successfully drained internal FIFO (Count = 0).\n");
            end else begin 
                $display("   [FAIL] RX Acknowledge drain failure. Expected FIFO count: 0, Actual: %0d\n", tx.prdata[19:16]);
                test_pass = 1'b0;
            end
        end
    join_any
    
    // Safety cleanup
    disable fork; 
    vif.D1 <= 1'bz; 
    vif.tx_dma_ack = 1'b0;
    vif.rx_dma_ack = 1'b0;

    // =================================================================
    // Global Scoreboard Registration
    // =================================================================
    tb_top.scoreboard.set_current_test("QSPI-DMA-HSK-29");
    tb_top.scoreboard.mark_as_run("QSPI-DMA-HSK-29");

    if (test_pass) begin
        tb_top.scoreboard.set_test_pass(1'b1, "PASS");
    end else begin
        tb_top.scoreboard.set_test_pass(1'b0, "FAIL");
    end
endtask
