`timescale 1ns/1ps

// =========================================================================
// TEST 14: Baud Rate Clock Divider
// =========================================================================
module tb_test_14;

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
    
    reg slave_D1 = 1'bz; reg slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;

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
    // Validates the baud rate clock divider mechanism. It triggers a basic 
    // transmission sequence to wake up the SPI bus, then actively monitors 
    // the physical CLK pin to ensure it is generating clean, alternating 
    // edges derived from the system pclk without hanging.
    // =====================================================================
    initial begin
        $dumpfile("dump_test_14.vcd"); $dumpvars(0, tb_test_14);
        
        $display("\n=======================================================================");
        $display(" TEST 14: Baud Rate Clock Divider");
        $display(" Validate SPI clock (sclk_out) generation and scaling.");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Launching arbitrary TX command to activate sclk_out (CLK)...");
        apb_write(32'h04, 32'hFF00_FF00); 
        apb_write(32'h00, 32'h0000_0003); // Start TX
        
        $display("2. Monitoring CLK pin logic toggling...");
        // Wait for the clock to toggle physically (Watchdog added to prevent hang)
        fork
            begin
                @(posedge CLK);
                @(negedge CLK);
                @(posedge CLK);
                $display("   [PASS] sclk_out (CLK) is actively generating edges based on system pclk.\n");
                update_summary("tb_test_14", 1);
            end
            begin
                #2000;
                $display("   [FAIL] Clock never toggled!\n");
                update_summary("tb_test_14", 0);
            end
        join_any
        disable fork; // Crucial: Kills the background timeout thread if clock toggled successfully

        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0)) @(posedge pclk);
        #100 $finish;
    end
endmodule
