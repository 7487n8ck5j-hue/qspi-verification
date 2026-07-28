`timescale 1ns/1ps

// =========================================================================
// TEST 39: SRAM Overrun / Back-Pressure Handling
// =========================================================================
module tb_test_39;

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
    // Pullups simulate physical board resistors. No mock slave is needed 
    // for this test as the focus is entirely on the internal SRAM FIFO 
    // boundary management and full-flag assertion.
    // =====================================================================
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    qspi_apb_master dut (.*);

    // Generate a 100MHz clock (Toggles every 5ns)
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // - update_summary: Safely writes the PASS/FAIL result to the log file.
    // - apb_write/read: Replicates a cycle-accurate AMBA APB protocol 
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
    // Validates SRAM overrun and back-pressure handling (QSPI-IND-LVL-39).
    // It intentionally pushes 10 words into an 8-word deep TX FIFO. The 
    // test passes if the hardware clamps the queue size at 8 and correctly 
    // asserts the TX_Full flag in the status/control register.
    // =====================================================================
    initial begin
        logic [31:0] val;
        bit test_pass = 1'b1;

        $dumpfile("dump_test_39.vcd"); $dumpvars(0, tb_test_39);
        $display("\n=======================================================================");
        $display(" TEST 39: SRAM Overrun / Back-Pressure Handling (QSPI-IND-LVL-39)");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Pushing 10 words into the 8-word TX FIFO...");
        for (int i=0; i<10; i++) begin
            apb_write(32'h04, 32'hA1A1_A1A1); 
        end

        apb_read(32'h00, val);

        if (dut.tx_fifo_cnt == 4'd8 && val[5] == 1'b1) begin
            $display("   [PASS] Hardware throttled queue at 8. TX_Full flag successfully asserted.\n");
        end else begin
            $display("   [FAIL] Hardware failed to clamp queue size. (Count: %0d, TX_Full: %b)\n", dut.tx_fifo_cnt, val[5]);
            test_pass = 1'b0;
        end

        update_summary("tb_test_39", test_pass);
        #100 $finish;
    end
endmodule
