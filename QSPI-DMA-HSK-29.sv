`timescale 1ns/1ps

// =========================================================================
// TEST 29: DMA Peripheral Handshaking
// =========================================================================
module tb_test_29;

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
    // D3, D2, and D0 are tied to high impedance ('z') since they are unused. 
    // D1 (MISO) is conditionally driven by the mock slave to feed data back 
    // to the master during read operations.
    // =====================================================================
    logic slave_D1 = 1'bz; logic slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;
    assign D3 = 1'bz; assign D2 = 1'bz; assign D0 = 1'bz;

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
    // Mock SPI Flash Memory (The Slave)
    // ---------------------------------------------------------------------
    // Simulates a safe flash response. The asynchronous posedge CS_n reset 
    // ensures the slave cleanly aborts its transmission and returns to 
    // high impedance when the chip select line is de-asserted. Drives logic
    // HIGH ('1') when active.
    // =====================================================================
    // Safe Mock Flash: Drives 1s when active, safely resets on CS_n high
    always @(negedge CLK or posedge CS_n) begin
        if (CS_n) begin
            slave_oe <= 0;
            slave_D1 <= 1'bz;
        end else begin
            slave_oe <= 1;
            slave_D1 <= 1'b1;
        end
    end

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Validates AXI-like DMA integration and peripheral handshaking.
    // Configures the DMA boundaries and checks the hardware's capability 
    // to automatically raise DMA requests (tx_dma_req/rx_dma_req) and properly 
    // update internal FIFOs when the system acknowledges (tx_dma_ack/rx_dma_ack).
    // =====================================================================
    initial begin
        bit test_pass = 1'b1;
        
        $dumpfile("dump_test_29.vcd"); $dumpvars(0, tb_test_29);
        $display("\n=======================================================================");
        $display(" TEST 29: DMA Peripheral Handshaking (Read/Write)");
        $display(" Validate AXI-like DMA integration");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Configuring DMA boundaries: RX Threshold = 1, TX Threshold = 1...");
        // RX Thresh=1 (Bits 23:16), TX Thresh=1 (Bits 15:8), En TX/RX = 1 -> 0x0001_0103
        apb_write(32'h28, 32'h0001_0103); 

        // --- TX Handshake Test ---
        $display("2. Validating TX Handshake integration...");
        wait(tx_dma_req == 1'b1);
        $display("   [PASS] TX DMA Request raised automatically.");
        
        @(negedge pclk); tx_dma_ack = 1'b1; // System pushes data
        @(negedge pclk); tx_dma_ack = 1'b0; 
        #10;
        
        if (dut.tx_fifo_cnt == 4'd1) begin
            $display("   [PASS] TX Acknowledge successfully populated FIFO.");
        end else begin
            $display("   [FAIL] TX Acknowledge failed.");
            test_pass = 1'b0;
        end

        // --- RX Handshake Test ---
        $display("3. Validating RX Handshake integration...");
        apb_write(32'h00, 32'h0000_0001); // Start RX
        
        // Wait for flash to feed RX FIFO
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0)) @(posedge pclk);
        
        wait(rx_dma_req == 1'b1);
        $display("   [PASS] RX DMA Request raised automatically after payload receipt.");
        
        @(negedge pclk); rx_dma_ack = 1'b1; // System pops data
        @(negedge pclk); rx_dma_ack = 1'b0; 
        #10;

        if (dut.rx_fifo_cnt == 4'd0) begin
            $display("   [PASS] RX Acknowledge successfully drained FIFO.\n");
        end else begin 
            $display("   [FAIL] RX Acknowledge failed.\n");
            test_pass = 1'b0;
        end

        update_summary("tb_test_29", test_pass);
        #100 $finish;
    end
endmodule
