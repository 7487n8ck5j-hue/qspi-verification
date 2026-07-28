`timescale 1ns/1ps

// =========================================================================
// TEST 38: AHB Address Remap / Decoder (QSPI-AHB-REG-38)
// =========================================================================
module tb_test_38;

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
    // floating to an unknown 'x' state when the bus is idle. A mock slave 
    // is unnecessary as the test focuses entirely on internal AMBA routing.
    // =====================================================================
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    qspi_apb_master dut (.*);
    
    // Generate a 100MHz clock (Toggles every 5ns)
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // - update_summary: Safely writes the PASS/FAIL result to the log file.
    // Note: Standard apb_write/read tasks are omitted here since the bus 
    // is driven manually to easily capture asynchronous error flags.
    // =====================================================================
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
    // Validates the AHB address remap and decoder logic. It manually drives 
    // a read request to an out-of-bounds address map (0x1000_0000). The test 
    // passes if the hardware either asserts a hard-fault flag (pslverr) or 
    // returns the expected silent debug fault code (0x44) on the data bus.
    // =====================================================================
    initial begin
        bit captured_err = 0;
        logic [31:0] captured_data = 0;
        
        $dumpfile("dump_test_38.vcd"); $dumpvars(0, tb_test_38);
        $display("\n=======================================================================");
        $display(" TEST 38: AHB Address Remap / Decoder (QSPI-AHB-REG-38)");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);
        
        @(negedge pclk); psel=1; pwrite=0; paddr=32'h1000_0000; pstrb=4'b0000;
        @(negedge pclk); penable=1; 
        
        wait(pready);
        
        // Capture both the slave error flag AND the data bus
        captured_err = pslverr;
        captured_data = prdata;
        
        // Pass if the hardware uses the hard-fault flag (pslverr) OR the silent debug fault code (0x44)
        if (captured_err === 1'b1 || captured_data === 32'h0000_0044) begin 
            $display("   [PASS] Hardware Translation safely rejected out-of-bounds map. (pslverr active OR fault code 0x44 returned).\n");
            update_summary("tb_test_38", 1);
        end else begin 
            $display("   [FAIL] Translation logic failed to assert error on out-of-bounds access. Data returned: %h\n", captured_data);
            update_summary("tb_test_38", 0);
        end

        // Deassert APB bus cleanly
        @(negedge pclk); psel=0; penable=0;

        #100 $finish;
    end
endmodule
