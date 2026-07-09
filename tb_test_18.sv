`timescale 1ns/1ps

// =========================================================================
// TEST 18: STIG Memory Bank
// =========================================================================
module tb_test_18;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    logic slave_D1 = 1'bz; logic slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;
    assign D3 = 1'bz; assign D2 = 1'bz; assign D0 = 1'bz;

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

    // Safe Mock Flash: Aborts cleanly if CS_n is de-asserted early
    always @(negedge CLK or posedge CS_n) begin
        if (CS_n) begin
            slave_oe <= 0;
            slave_D1 <= 1'bz;
        end else begin
            slave_oe <= 1;
            slave_D1 <= ~slave_D1; // Feed alternating bits for memory bank tracking
        end
    end

    initial begin
        $dumpfile("dump_test_18.vcd"); $dumpvars(0, tb_test_18);
        $display("\n=======================================================================");
        $display(" TEST 18: STIG Memory Bank (QSPI-APB-SRD-18)");
        $display(" Validate extended read transfers (>8 Bytes)");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Initiating extended transfer sequence (3 words / 12 bytes)...");
        // Issue 3 consecutive Start commands before clearing the buffer
        apb_write(32'h00, 32'h0000_0001); 
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0)) @(posedge pclk);
        
        apb_write(32'h00, 32'h0000_0001); 
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0)) @(posedge pclk);
        
        apb_write(32'h00, 32'h0000_0001); 
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0)) @(posedge pclk);

        $display("2. Checking RX FIFO Depth...");
        #10;
        if (dut.rx_fifo_cnt == 4'd3) begin
            $display("   [PASS] Extended transfer accumulated correctly in memory bank.\n");
            update_summary("tb_test_18", 1);
        end else begin
            $display("   [FAIL] Internal queue did not hold expected depth. Got: %d\n", dut.rx_fifo_cnt);
            update_summary("tb_test_18", 0);
        end

        #100 $finish;
    end
endmodule
