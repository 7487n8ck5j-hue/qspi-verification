`timescale 1ns/1ps

// =========================================================================
// TEST 16: Hardware Reset Pin Routing
// =========================================================================
module tb_test_16;

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
        bit test_pass = 1'b1; // Accumulator for multi-stage test
        
        $dumpfile("dump_test_16.vcd"); $dumpvars(0, tb_test_16);
        $display("\n=======================================================================");
        $display(" TEST 16: Hardware Reset Pin Routing");
        $display(" Validate dedicated target reset signals.");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Checking default pin state (Expected: HIGH)...");
        #10;
        if (FLASH_RST_n === 1'b1) begin
            $display("   [PASS] Default reset state is unasserted (HIGH).");
        end else begin 
            $display("   [FAIL] Default reset state is asserted or floating.");
            test_pass = 1'b0;
        end

        $display("2. Activating physical hardware reset via CTRL_REG Bit 2...");
        // Clear Bit 2 to pull FLASH_RST_n LOW
        apb_write(32'h00, 32'h0000_0000); 
        #20;
        
        if (FLASH_RST_n === 1'b0) begin
            $display("   [PASS] FLASH_RST_n safely pulled LOW to reset external device.");
        end else begin 
            $display("   [FAIL] FLASH_RST_n did not respond to control register.");
            test_pass = 1'b0;
        end

        $display("3. Releasing physical hardware reset...");
        // Set Bit 2 to return FLASH_RST_n HIGH
        apb_write(32'h00, 32'h0000_0004); 
        #20;

        if (FLASH_RST_n === 1'b1) begin
            $display("   [PASS] FLASH_RST_n successfully released to HIGH.\n");
        end else begin 
            $display("   [FAIL] FLASH_RST_n remained stuck LOW.\n");
            test_pass = 1'b0;
        end

        // Log final unified result to Makefile
        update_summary("tb_test_16", test_pass);
        
        #100 $finish;
    end
endmodule
