`timescale 1ns/1ps

// =========================================================================
// TEST 03: Status Register Polling (WIP Check)
// =========================================================================
module tb_test_03;
    
    // =====================================================================
    // Signal Declarations
    // ---------------------------------------------------------------------
    // Defines all the physical pins connecting to the QSPI Master.
    // 'logic' is used for testbench-driven inputs, while 'wire' is used
    // for outputs coming from the Design Under Test (DUT).
    // =====================================================================
    logic pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; logic [3:0] pstrb = 4'b1111;
    logic rx_dma_ack = 0, tx_dma_ack = 0;
    
    wire [31:0] prdata; wire pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    // =====================================================================
    // Bus Terminations & DUT Instantiation
    // ---------------------------------------------------------------------
    // Pullups simulate physical board resistors, preventing data lines from
    // floating to an unknown 'x' state. D1 (MISO) is dynamically driven 
    // by the mock slave only when 'slave_oe' is active.
    // =====================================================================
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    
    reg slave_D1 = 1'bz; reg slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;

    qspi_apb_master dut (.*);
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // - update_summary: Safely writes the PASS/FAIL result to the log file.
    // - apb_write/read: Replicates a cycle-accurate AMBA APB protocol.
    // =====================================================================
    task automatic update_summary(input string test_name, input bit pass);
        int fd = $fopen("regression_summary.txt", "a");
        if (fd) begin
            $fdisplay(fd, "%s: %s", test_name, pass ? "PASS" : "FAIL");
            $fclose(fd);
        end
    endtask

    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; wait(pready);
        @(negedge pclk); psel=0; penable=0;
    endtask

    task automatic apb_read(input [31:0] addr, output logic [31:0] data);
        @(negedge pclk); psel=1; pwrite=0; paddr=addr; pstrb=4'b0000;
        @(negedge pclk); penable=1; wait(pready); data = prdata;
        @(negedge pclk); psel=0; penable=0;
    endtask

    // =====================================================================
    // Mock SPI Flash Memory (The Slave)
    // ---------------------------------------------------------------------
    // Simulates a Flash memory chip responding to a Status Register read.
    // It intentionally forces the Write-In-Progress (WIP) bit (the LSB) 
    // to '1' for the first 3 polls to simulate the flash being busy, 
    // then clears it to '0' to signal readiness.
    // =====================================================================
    initial begin
        int poll_count = 0;
        forever begin
            @(negedge CS_n);
            slave_oe = 1;
            for (int i=7; i>=0; i--) begin 
                slave_D1 = (i == 0 && poll_count < 3) ? 1'b1 : 1'b0;
                if (i > 0) @(negedge CLK);
            end
            poll_count++;
            @(posedge CS_n); 
            slave_oe = 0; slave_D1 = 1'bz;
        end
    end

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Triggers the hardware to read the SPI Flash status register. 
    // It loops and polls the returned data until the WIP bit (Bit 0) 
    // is cleared, proving the APB master can handle software polling.
    // =====================================================================
    initial begin
        logic [31:0] val = 32'h0000_0001; 
        int timeout_ctr = 0;
        
        $dumpfile("dump_test_03.vcd"); $dumpvars(0, tb_test_03);
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        // Keep polling via APB as long as the WIP bit is 1, up to 50 attempts
        while (val[0] == 1'b1 && timeout_ctr < 50) begin
            apb_write(32'h00, 32'h0000_0001); 
            while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0)) @(posedge pclk);
            apb_read(32'h08, val);
            timeout_ctr++;
        end

        // Evaluate and log the final outcome
        if (val[0] == 1'b0) begin
            $display("   [PASS] Flash READY. Sequence exited cleanly.");
            update_summary("tb_test_03", 1);
        end else begin
            $display("   [FAIL] Timed out waiting for ready.");
            update_summary("tb_test_03", 0);
        end
        #100 $finish;
    end
endmodule
