`timescale 1ns/1ps

// =========================================================================
// TEST 04: Legacy SPI Mode FIFO Thresholds (TX)
// =========================================================================
module tb_test_04;

    // =====================================================================
    // Signal Declarations
    // ---------------------------------------------------------------------
    // Defines all the physical pins connecting to the QSPI Master.
    // 'logic' is used for testbench-driven inputs, while 'wire' is used
    // for outputs coming from the Design Under Test (DUT).
    // =====================================================================
    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    // =====================================================================
    // Bus Terminations & DUT Instantiation
    // ---------------------------------------------------------------------
    // Pullups simulate physical board resistors, preventing data lines from
    // floating to an unknown 'x' state when not actively driven.
    // The (.*) syntax automatically connects wires to matching DUT ports.
    // =====================================================================
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    
    qspi_apb_master dut (.*);
    
    // Generate a 100MHz clock (Toggles every 5ns)
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // - update_summary: Safely writes the PASS/FAIL result to the log file.
    // - apb_write: Replicates a cycle-accurate AMBA APB write protocol.
    // =====================================================================
    task automatic update_summary(input string test_name, input bit pass);
        int fd = $fopen("regression_summary.txt", "a");
        if (fd) begin
            $fdisplay(fd, "%s: %s", test_name, pass ? "PASS" : "FAIL");
            $fclose(fd);
        end
    endtask

    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; wait(pready);
        @(negedge pclk); psel=0; penable=0;
    endtask

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Validates the TX DMA Threshold functionality. It configures the DMA
    // threshold, overfills the FIFO so the request shouldn't trigger yet,
    // starts the SPI transmission, and ensures the DMA request asserts 
    // exactly when the FIFO drains down to the programmed threshold limit.
    // =====================================================================
    initial begin
        // Initialize waveform dumping and reset the hardware
        $dumpfile("dump_test_04.vcd"); $dumpvars(0, tb_test_04);
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        // 1. Configure DMA Control Register (0x28). 
        // Example: 0x0201 sets TX DMA threshold to 2 and enables TX DMA (Bit 0).
        apb_write(32'h28, 32'h0000_0201); 
        
        // 2. Pre-fill the TX FIFO with 3 words (Above the threshold of 2)
        for (int i=0; i<3; i++) begin
            apb_write(32'h04, 32'hA0A0_0000);
        end

        #10;
        
        // 3. Negative Check: Ensure the DMA request doesn't fire while FIFO > threshold
        if (tx_dma_req !== 1'b0) begin
            $display("   [FAIL] Interrupt triggered too early.");
            update_summary("tb_test_04", 0);
            $finish;
        end

        // 4. Start the SPI transmission to begin draining the TX FIFO
        apb_write(32'h00, 32'h0000_0003); // Start TX

        // 5. Positive Check: Wait for the FIFO to drain and trigger the DMA request
        fork
            begin
                // Monitor for the request assertion
                wait(tx_dma_req == 1'b1);
                $display("   [PASS] Level thresholds successfully triggered.");
                update_summary("tb_test_04", 1);
            end
            begin
                // Safety timeout to prevent infinite simulation hangs
                #2000;
                $display("   [FAIL] Timeout: TX threshold request never triggered.");
                update_summary("tb_test_04", 0);
            end
        join_any
        
        // Kill whichever branch didn't finish first
        disable fork;

        #100 $finish;
    end
endmodule
