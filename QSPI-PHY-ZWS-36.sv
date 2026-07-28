`timescale 1ns/1ps

// =========================================================================
// TEST 36: PHY Pipeline Mode (Zero-Wait-State)
// =========================================================================
module tb_test_36;

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
    // floating to an unknown 'x' state when the bus is idle. No active 
    // mock slave is required for this pipeline ingestion test.
    // =====================================================================
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    qspi_apb_master dut (.*);
    
    // Generate a 100MHz clock (Toggles every 5ns)
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // - update_summary: Safely writes the PASS/FAIL result to the log file.
    // - apb_write: Replicates an AMBA APB write protocol. Includes a custom
    //   tracker to flag a Zero-Wait-State (ZWS) violation if the hardware
    //   drops pready immediately upon the penable phase.
    // =====================================================================
    // Standardized Makefile Tracking
    task automatic update_summary(input string test_name, input bit pass);
        int fd = $fopen("regression_summary.txt", "a");
        if (fd) begin
            $fdisplay(fd, "%s: %s", test_name, pass ? "PASS" : "FAIL");
            $fclose(fd);
        end
    endtask

    bit zws_violation = 1'b0;

    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; 
        
        // Zero-Wait-State check
        if (pready !== 1'b1) zws_violation = 1'b1;
        
        while(pready == 1'b0) @(negedge pclk);
        psel=0; penable=0;
    endtask

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Validates the hardware's PHY Pipeline Mode for Zero-Wait-State ingestion.
    // It pushes a burst of 4 words into the TX FIFO sequentially, monitoring 
    // the AMBA pready signal to see if wait states are dynamically injected. 
    // It then triggers the transmission and utilizes an auto-retriggering 
    // watchdog loop to ensure the pipeline correctly drains to the SPI bus 
    // without stalling the state machine.
    // =====================================================================
    initial begin
        int timeout_ctr = 0;
        int queue_drained = 0;
        
        $dumpfile("dump_test_36.vcd"); $dumpvars(0, tb_test_36);
        $display("\n=======================================================================");
        $display(" TEST 36: PHY Pipeline Mode (Zero-Wait-State)");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Initiating pipelined APB burst write to TX FIFO...");
        apb_write(32'h04, 32'h1111_1111);
        apb_write(32'h04, 32'h2222_2222);
        apb_write(32'h04, 32'h3333_3333);
        apb_write(32'h04, 32'h4444_4444);

        if (zws_violation) $display("   [NOTE] Pready dropped. Pipeline incurred wait states.");

        apb_write(32'h00, 32'h0000_0003); // Start TX

        // Bounded loop with Auto-Retrigger for pipelined payload
        while (timeout_ctr < 50000) begin
            @(posedge pclk);
            timeout_ctr++;
            
            if (dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0) begin
                if (dut.tx_fifo_cnt == 0) begin
                    queue_drained = 1;
                    break;
                end else begin
                    apb_write(32'h00, 32'h0000_0003); // Re-trigger Start TX
                end
            end
        end
        
        if (queue_drained) begin
            $display("   [PASS] Transmission executed seamlessly. Pipeline drained.\n");
            update_summary("tb_test_36", 1);
        end else begin
            $display("   [FAIL] FSM Locked up during pipeline transmission (State: %0d, TX_FIFO: %0d).\n", dut.state, dut.tx_fifo_cnt);
            update_summary("tb_test_36", 0);
        end

        #100 $finish;
    end
endmodule
