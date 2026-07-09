`timescale 1ns/1ps

// =========================================================================
// TEST 34: SRAM Partition Allocation
// =========================================================================
module tb_test_34;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    assign D3 = 1'bz; assign D2 = 1'bz; assign D1 = 1'bz; assign D0 = 1'bz;

    qspi_apb_master dut (.*);
    always #5 pclk = ~pclk;

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

    initial begin
        $dumpfile("dump_test_34.vcd"); $dumpvars(0, tb_test_34);
        $display("\n=======================================================================");
        $display(" TEST 34: SRAM Partition Allocation");
        $display(" Validate shared memory management");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Constraining SRAM allocation blocks (TX Limit = 2) via INDAC Config...");
        apb_write(32'h28, 32'h0000_0201); // Setting a strict threshold to 2
        
        $display("2. Attempting to overload allocated INDAC partition...");
        // Push 4 words into the constrained block
        for (int i=0; i<4; i++) begin
            apb_write(32'h04, 32'hF0F0_0F0F);
        end

        #20;
        
        // Asserting that hardware DMA request behaves accurately based on the adjusted limit
        if (tx_dma_req === 1'b0) begin
            $display("   [PASS] Shared memory allocation obeyed. DMA queue request muted above partition limits.\n");
            update_summary("tb_test_34", 1);
        end else begin
            $display("   [FAIL] Partition allocation ignored by hardware.\n");
            update_summary("tb_test_34", 0);
        end

        #100 $finish;
    end
endmodule
