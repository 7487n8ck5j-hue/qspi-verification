`timescale 1ns/1ps

// =========================================================================
// TEST 24: Custom Hardware Status Polling (QSPI-PHY-POL-24)
// =========================================================================
module tb_test_24;

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
    // Pullups/weak highs are actively driven here on the Quad pins to 
    // prevent the internal FSM from locking up on 'x' states during idle.
    // =====================================================================
    // Use weak highs to prevent 'X' state lockups in the FSM
    assign D3 = 1'b1; assign D2 = 1'b1; assign D0 = 1'b1;
    
    reg slave_D1 = 1'b1; reg slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'b1;

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
    // Mock SPI Flash Memory (The Slave)
    // ---------------------------------------------------------------------
    // Simulates a Flash device that is temporarily busy processing a command. 
    // It cleanly waits out the 8-cycle command phase before driving the bus. 
    // It returns a "Busy" status (Bit 7 = 1) for the first two polls, and 
    // a "Ready" status (Bit 7 = 0) on the third attempt.
    // =====================================================================
    // Fixed Mock Flash: properly waits out the command phase before driving
    initial begin
        int poll_count = 0;
        forever begin
            @(negedge CS_n);
            for (int i=0; i<8; i++) @(negedge CLK); // Skip command phase
            
            slave_oe = 1;
            for (int i=7; i>=0; i--) begin 
                @(negedge CLK); #1;
                if (i == 7) slave_D1 = (poll_count < 2) ? 1'b1 : 1'b0;
                else slave_D1 = 1'b0;
            end
            poll_count++;
            
            @(posedge CS_n); #1; slave_oe = 0; slave_D1 = 1'b1;
        end
    end

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Validates the hardware's capability to safely handle continuous 
    // status polling without locking up. The test repeatedly queries the 
    // device's status register (e.g., command 0x70) until the busy flag 
    // clears, using timeout counters to prevent infinite simulation loops.
    // =====================================================================
    initial begin
        logic [31:0] val = 32'h0000_0080;
        int poll_ctr = 0;
        int apb_timeout = 0;
        
        $dumpfile("dump_test_24.vcd"); $dumpvars(0, tb_test_24);
        $display("\n=======================================================================");
        $display(" TEST 24: Custom Hardware Status Polling");
        $display(" Validate continuous looping for device status bit.");
        $display("=======================================================================\n");

        presetn = 0; #33; presetn = 1; @(posedge pclk);

        while (val[7] == 1'b1 && poll_ctr < 50) begin
            apb_write(32'h04, 32'h7000_0000); 
            apb_write(32'h14, 32'h0000_0002); // Transfer Length: 2 bytes
            apb_write(32'h00, 32'h0000_0001); // Start RX
            
            apb_timeout = 0;
            while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && apb_timeout < 1000) begin
                @(posedge pclk);
                apb_timeout++;
            end
            
            apb_read(32'h08, val);
            if (val[7] == 1'b1) $display("   Status Register Bit 7 is HIGH (Busy). Re-issuing query...");
            else $display("   [PASS] Target hardware resolved block. Polling concluded properly.\n");
            
            poll_ctr++;
        end

        if (poll_ctr >= 50) begin
            $display("   [FAIL] Hardware locked up. Polling limit exceeded.");
            update_summary("tb_test_24", 0);
        end else if (apb_timeout >= 1000) begin
            $display("   [FAIL] APB internal state machine timed out.");
            update_summary("tb_test_24", 0);
        end else begin
            update_summary("tb_test_24", 1);
        end

        #100 $finish;
    end
endmodule
