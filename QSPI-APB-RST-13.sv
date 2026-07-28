`timescale 1ns/1ps

// =========================================================================
// TEST 13: APB Register POR Default Validation
// =========================================================================
module tb_test_13;

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
    // floating to an unknown 'x' state when the bus is idle.
    // =====================================================================
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);

    qspi_apb_master dut (.*);
    
    // Generate a 100MHz clock (Toggles every 5ns)
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // - update_summary: Safely writes the PASS/FAIL result to the log file.
    // - apb_read: Replicates a cycle-accurate AMBA APB read protocol 
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

    // Robust AMBA Polling (Read Only Needed Here)
    task automatic apb_read(input [31:0] addr, output logic [31:0] data);
        @(negedge pclk); psel=1; pwrite=0; paddr=addr; pstrb=4'b0000;
        @(negedge pclk); penable=1; 
        do begin @(negedge pclk); end while(pready == 1'b0);
        data = prdata;
        psel=0; penable=0;
    endtask

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Validates the Power-On Reset (POR) state of the hardware. It asserts
    // the system reset and reads back key memory-mapped control registers 
    // to ensure they initialize to their safe architectural default values 
    // before any software configuration occurs.
    // =====================================================================
    initial begin
        logic [31:0] val;
        bit test_pass = 1'b1;
        
        $dumpfile("dump_test_13.vcd"); $dumpvars(0, tb_test_13);
        $display("\n=======================================================================");
        $display(" TEST 13: APB Register POR Default Validation");
        $display(" Validate Power-On Reset (POR) register states.");
        $display("=======================================================================\n");
        
        $display("1. Asserting and de-asserting hardware presetn...");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("2. Checking architectural defaults...");
        
        apb_read(32'h00, val);
        if (val === 32'h0000_0044) begin
            $display("   [PASS] CTRL_REG (0x00) POR is 0x0000_0044");
        end else begin 
            $display("   [FAIL] CTRL_REG POR Mismatch! Got: %h", val);
            test_pass = 1'b0;
        end

        apb_read(32'h14, val);
        if (val === 32'h0000_0000) begin
            $display("   [PASS] DUMMY_CTRL (0x14) POR is 0x0000_0000");
        end else begin 
            $display("   [FAIL] DUMMY_CTRL POR Mismatch! Got: %h", val);
            test_pass = 1'b0;
        end

        apb_read(32'h24, val);
        if (val === 32'h0000_0000) begin
            $display("   [PASS] TIMEOUT_CTRL (0x24) POR is 0x0000_0000");
        end else begin 
            $display("   [FAIL] TIMEOUT_CTRL POR Mismatch! Got: %h", val);
            test_pass = 1'b0;
        end

        apb_read(32'h28, val);
        if (val === 32'h0000_0000) begin
            $display("   [PASS] DMA_CTRL (0x28) POR is 0x0000_0000\n");
        end else begin 
            $display("   [FAIL] DMA_CTRL POR Mismatch! Got: %h\n", val);
            test_pass = 1'b0;
        end

        // Log final unified result to Makefile
        update_summary("tb_test_13", test_pass);
        
        #100 $finish;
    end
endmodule
