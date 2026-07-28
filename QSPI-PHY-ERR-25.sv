`timescale 1ns/1ps

// =========================================================================
// TEST 25: Polling Expiration Timeout (QSPI-PHY-ERR-25)
// =========================================================================
module tb_test_25;

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
    // All Quad-SPI data lines are explicitly tied to logic HIGH (1'b1) 
    // to prevent 'X' state propagation through the FSM during the 
    // artificially long wait cycles.
    // =====================================================================
    assign D3 = 1'b1; assign D2 = 1'b1; assign D1 = 1'b1; assign D0 = 1'b1;

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
    // Validates the hardware polling timeout mechanism. It programs a strict 
    // expiration limit in the TIMEOUT_CTRL register, then intentionally 
    // triggers an excessively long (4096-byte) operation. The test passes 
    // if the hardware watchdog correctly interrupts (asserts IRQ) before 
    // the simulator's absolute timeout is reached.
    // =====================================================================
    initial begin
        int timeout_ctr = 0; 
        
        $dumpfile("dump_test_25.vcd"); $dumpvars(0, tb_test_25);
        $display("\n=======================================================================");
        $display(" TEST 25: Polling Expiration Timeout (QSPI-PHY-ERR-25)");
        $display(" Validate hardware polling timeout mechanism");
        $display("=======================================================================\n");

        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Binding strict transaction expiration limit (0x24)...");
        apb_write(32'h24, 32'h8000_004B); // Enable timer + set limit

        $display("2. Triggering excessively long operation...");
        apb_write(32'h14, 32'h0000_1000); // 4096 bytes (Guarantees timeout)
        apb_write(32'h00, 32'h0000_0809); // Start + Ints En

        // Wait for the hardware interrupt to assert, bounded by a safe limit
        while(irq == 1'b0 && timeout_ctr < 1000) begin
            @(posedge pclk);
            timeout_ctr++;
        end

        // Evaluate outcome
        if (timeout_ctr >= 1000) begin
            $display("   [FAIL] Simulator timed out. IRQ never asserted.\n");
            update_summary("tb_test_25", 0);
        end else begin
            $display("   [PASS] Watchdog efficiently terminated operation. IRQ Asserted.\n");
            update_summary("tb_test_25", 1);
        end

        #100 $finish;
    end
endmodule
