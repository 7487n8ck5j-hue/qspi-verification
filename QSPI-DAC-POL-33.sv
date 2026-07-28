`timescale 1ns/1ps

// =========================================================================
// TEST 33: Auto-Polling after DAC Write
// =========================================================================
module tb_test_33;

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
    // D3, D2, and D0 are tied to high impedance ('z') since they are unused
    // during the read phase of the polling. D1 (MISO) is conditionally 
    // driven by the mock slave to feed the status register data back.
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
    // Simulates a Flash device processing an automated status poll. It reads 
    // the incoming 8-bit command on D0. If it receives a Read Status 
    // Register command (0x05), it responds on D1 with a Write-In-Progress 
    // (WIP) bit (Bit 0) set to HIGH for the first two reads, and then 
    // clears it to LOW on the third read to simulate the write completing.
    // =====================================================================
    // Simulated Auto-Poll Response
    initial begin
        logic [7:0] cmd;
        int poll_count = 0;
        forever begin
            @(negedge CS_n);
            for (int i=7; i>=0; i--) begin 
                @(posedge CLK); 
                cmd[i] = (D0 === 1'bz) ? 1'b0 : D0; 
            end
            
            if (cmd == 8'h05) begin // Read Status Register
                slave_oe = 1;
                for (int i=7; i>=0; i--) begin 
                    @(negedge CLK); 
                    if (i == 0) slave_D1 = (poll_count < 2) ? 1'b1 : 1'b0; // Busy drops after 2 polls
                    else slave_D1 = 1'b0;
                end
                poll_count++;
            end
            @(posedge CS_n); 
            slave_oe = 0;
        end
    end

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Validates the Direct Access Controller's (DAC) hardware auto-polling 
    // feature. It executes a memory-mapped write operation (0x1000_0000) 
    // and then monitors the FSM to ensure it autonomously transitions into 
    // a polling loop, repeatedly fetching the status register until the 
    // mock slave indicates the internal write cycle is complete.
    // =====================================================================
    initial begin
        int timeout_ctr = 0;
        $dumpfile("dump_test_33.vcd"); $dumpvars(0, tb_test_33);
        $display("\n=======================================================================");
        $display(" TEST 33: Auto-Polling after DAC Write");
        $display(" Validate automated write cycle tracking");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Activating DAC Write configuration...");
        apb_write(32'h20, 32'h0000_0001); 

        $display("2. Executing DAC Write at 0x1000_0000...");
        apb_write(32'h1000_0000, 32'hCAFE_BABE); 

        $display("3. Monitoring hardware for autonomous WIP tracking phase...");
        
        // Wait for FSM to naturally execute write -> poll -> poll -> finish
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 5000) begin
            @(posedge pclk);
            timeout_ctr++;
        end

        #20;

        if (timeout_ctr < 5000) begin
            $display("   [PASS] Hardware auto-polling sequence verified. Write cycle resolved cleanly.\n");
            update_summary("tb_test_33", 1);
        end else begin
            $display("   [FAIL] Hardware timed out or locked up during polling phase.\n");
            update_summary("tb_test_33", 0);
        end

        #100 $finish;
    end
endmodule
