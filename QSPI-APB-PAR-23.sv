`timescale 1ns/1ps

// =========================================================================
// TEST 23: SRAM Partition Configuration
// =========================================================================
module tb_test_23;

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
    // In this SRAM partition test, the external flash bus is unused. All 
    // data lines (D0-D3) are tied to high impedance ('z') as the focus 
    // is entirely on internal DMA threshold and memory division logic.
    // =====================================================================
    assign D3 = 1'bz; assign D2 = 1'bz; assign D1 = 1'bz; assign D0 = 1'bz;

    qspi_apb_master dut (.*);
    
    // Generate a 100MHz clock (Toggles every 5ns)
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // - update_summary: Safely writes the PASS/FAIL result to the log file.
    // - apb_write: Replicates a cycle-accurate AMBA APB write protocol 
    //   using a do-while loop to robustly wait for pready assertion.
    // =====================================================================
    // Standardized Makefile Tracking
    task automatic update_summary(input string test_name, input bit pass);
        int fd = $fopen("regression_summary.txt", "a");
        if (fd) begin
            $fdisplay(fd, "%s: %s", test_name, pass ? "PASS" : "FAIL");
            $fclose(fd);
        end
    endtask

    // Robust AMBA Polling
    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; 
        do begin @(negedge pclk); end while(pready == 1'b0);
        psel=0; penable=0;
    endtask

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Validates the internal SRAM memory division by configuring strict 
    // threshold limits for the DMA controller. It verifies that the TX 
    // boundary logic correctly requests data when empty, and the RX 
    // boundary logic correctly suppresses read requests when empty.
    // =====================================================================
    initial begin
        bit test_pass = 1'b1;
        
        $dumpfile("dump_test_23.vcd"); $dumpvars(0, tb_test_23);
        $display("\n=======================================================================");
        $display(" TEST 23: SRAM Partition Configuration (QSPI-APB-PAR-23)");
        $display(" Validate internal SRAM memory division");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Configuring strict SRAM partition thresholds (DMA_CTRL)...");
        // RX Threshold = 4 (Bits 23:16), TX Threshold = 4 (Bits 15:8), Enable Both -> 0x0004_0403
        apb_write(32'h28, 32'h0004_0403); 

        $display("2. Verifying TX boundary logic response...");
        #10;
        if (tx_dma_req === 1'b1) begin
            $display("   [PASS] TX Memory partition evaluated correctly (Empty queue requested data).");
        end else begin
            $display("   [FAIL] TX Memory partition evaluation failed.");
            test_pass = 1'b0;
        end

        $display("3. Verifying RX boundary logic response...");
        if (rx_dma_req === 1'b0) begin
            $display("   [PASS] RX Memory partition evaluated correctly (Empty queue blocked read request).\n");
        end else begin
            $display("   [FAIL] RX Memory partition evaluation failed.\n");
            test_pass = 1'b0;
        end

        // Log final unified result to Makefile
        update_summary("tb_test_23", test_pass);
        
        #100 $finish;
    end
endmodule
