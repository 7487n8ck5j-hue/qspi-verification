`timescale 1ns/1ps

// =========================================================================
// TEST 12: At-Speed Scan Stress Toggle Check
// =========================================================================
module tb_test_12;

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
    // Simulates an At-Speed Scan stress test to evaluate power and timing 
    // integrity. By filling the FIFO with alternating bits (0xAAAA_5555), 
    // it maximizes the toggle rate on the physical SPI bus. A bounded wait 
    // ensures the testbench catches FSM lockups without crashing the compiler.
    // =====================================================================
    initial begin
        int timeout_ctr = 0;
        
        $dumpfile("dump_test_12.vcd"); $dumpvars(0, tb_test_12);
        $display("\n=======================================================================");
        $display(" TEST 12: At-Speed Scan Stress Toggle Check");
        $display("=======================================================================\n");

        presetn = 0; #33; presetn = 1; @(posedge pclk);

        // Push 8 alternating words into the FIFO to maximize switching activity
        for (int i=0; i<8; i++) begin
            apb_write(32'h04, 32'hAAAA_5555); 
        end
        apb_write(32'h00, 32'h0000_0003); // Start TX

        // BOUNDED WAIT TO PREVENT 137 CRASH
        // Ensures the simulator exits cleanly rather than hanging forever 
        // if the hardware state machine fails to return to IDLE (state 0).
        while(dut.state != 3'd0 && timeout_ctr < 2000) begin
            @(posedge pclk);
            timeout_ctr++;
        end

        // Evaluate whether the hardware cleared the stress test successfully
        if (timeout_ctr < 2000) begin
            $display("   [PASS] At-Speed toggle resolved without lockup.\n");
            update_summary("tb_test_12", 1);
        end else begin
            $display("   [FAIL] Hardware locked up. Bounded timeout reached.\n");
            update_summary("tb_test_12", 0);
        end
        
        #100 $finish;
    end
endmodule
