`timescale 1ns/1ps

// =========================================================================
// TEST 40: Hardware HOLD Pin Suspension
// =========================================================================
module tb_test_40;

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
    // CRITICAL: Pullups represent physical PCB traces holding unused pins 
    // High. In Standard/Single SPI mode, D3 acts as the active-low HOLD_n 
    // signal, so it must safely float high (High-Z) to prevent suspending 
    // the hardware transaction prematurely.
    // =====================================================================
    // CRITICAL: Pullups represent physical PCB traces holding unused pins High
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);

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
    // Validates Hardware HOLD Pin Suspension (QSPI-PHY-HSK-40). The test
    // initiates a TX operation in Single SPI mode (Quad OFF). It then 
    // samples the D3 pin during the active chip select window to ensure 
    // the hardware safely leaves the pin floating High-Z rather than 
    // driving it low and illegally suspending the transaction.
    // =====================================================================
    initial begin
        int timeout_ctr = 0;
        bit test_pass = 1'b1;

        $dumpfile("dump_test_40.vcd"); $dumpvars(0, tb_test_40);
        $display("\n=======================================================================");
        $display(" TEST 40: Hardware HOLD Pin Suspension (QSPI-PHY-HSK-40)");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        apb_write(32'h04, 32'h1234_5678); 
        apb_write(32'h00, 32'h0000_0003); // Start TX in SINGLE Mode (Quad is OFF)

        #20; 

        if (CS_n === 1'b0) begin
            if (D3 === 1'b1) begin
                $display("   [PASS] D3 (HOLD_n) safely floating High-Z / Pulled HIGH.");
            end else begin
                $display("   [FAIL] D3 driven LOW! Transaction illegally suspended.");
                test_pass = 1'b0;
            end
        end else begin 
            $display("   [FAIL] FSM failed to start.");
            test_pass = 1'b0;
        end

        // Bounded loop
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 1000) begin
            @(posedge pclk); timeout_ctr++;
        end

        update_summary("tb_test_40", test_pass);
        #100 $finish;
    end
endmodule
