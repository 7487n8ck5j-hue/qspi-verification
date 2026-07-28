`timescale 1ns/1ps

// =========================================================================
// TEST 19: Hardware Write Protection
// =========================================================================
module tb_test_19;

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
    // In this hardware protection test, all data lines are tied to high 
    // impedance ('z'). No external flash communication occurs because the 
    // focus is solely on the internal APB register address decoding and 
    // write-blocking logic.
    // =====================================================================
    assign D3 = 1'bz; assign D2 = 1'bz; assign D1 = 1'bz; assign D0 = 1'bz;

    qspi_apb_master dut (.*);
    
    // Generate a 100MHz clock (Toggles every 5ns)
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // - update_summary: Safely writes the PASS/FAIL result to the log file.
    // Note: Standard apb_write/read tasks are intentionally omitted here 
    // so the bus can be driven manually to catch asynchronous error flags.
    // =====================================================================
    // Standardized Makefile Tracking
    task automatic update_summary(input string test_name, input bit pass);
        int fd = $fopen("regression_summary.txt", "a");
        if (fd) begin
            $fdisplay(fd, "%s: %s", test_name, pass ? "PASS" : "FAIL");
            $fclose(fd);
        end
    endtask

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Validates block-level hardware address locking. It manually attempts 
    // an illegal memory-mapped write to a read-only destination (the RX FIFO 
    // register) to ensure the hardware either raises an AMBA Slave Error 
    // (pslverr) or safely discards the data without corrupting the register.
    // =====================================================================
    initial begin
        bit test_pass = 1'b1;
        
        $dumpfile("dump_test_19.vcd"); $dumpvars(0, tb_test_19);
        $display("\n=======================================================================");
        $display(" TEST 19: Hardware Write Protection (QSPI-AHB-ERR-19)");
        $display(" Validate block-level hardware address locking");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Attempting illegal memory-mapped WRITE to Read-Only RX_REG (0x08)...");
        
        // Manual AMBA drive to test error response asynchronously
        @(negedge pclk); psel=1; pwrite=1; paddr=32'h08; pwdata=32'hDEAD_BEEF; pstrb=4'b1111;
        @(negedge pclk); penable=1; 
        
        #1; // Sample the error flag asynchronously 
        
        if (pslverr === 1'b1) begin
            $display("   [PASS] Hardware Address Protection caught the illegal write. Slave Error Asserted.");
        end else begin
            $display("   [NOTE] Design logic ignores RO write. Checking if data was safely rejected...");
        end

        // Wait for pready using robust logic before clearing bus
        wait(pready);
        @(negedge pclk); psel=0; penable=0; #10;

        $display("2. Verifying RX_REG remains uncorrupted by illegal operation...");
        @(negedge pclk); psel=1; pwrite=0; paddr=32'h08; pstrb=4'b0000;
        @(negedge pclk); penable=1; 
        wait(pready); 
        
        if (prdata === 32'h0000_0000) begin
            $display("   [PASS] Memory successfully block-locked. Write blocked completely.\n");
        end else begin
            $display("   [FAIL] Hardware write protection bypassed. Data corrupted: %h\n", prdata);
            test_pass = 1'b0;
        end
            
        @(negedge pclk); psel=0; penable=0;

        // Log unified result to Makefile
        update_summary("tb_test_19", test_pass);
        #100 $finish;
    end
endmodule
