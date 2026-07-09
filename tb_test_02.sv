`timescale 1ns/1ps

// =========================================================================
// TEST 02: Hardware Flash Reset Pin Validation
// =========================================================================
module tb_test_02;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    
    reg slave_D1 = 1'bz; 
    reg slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;

    qspi_apb_master dut (.*);
    always #5 pclk = ~pclk;

    // FIX: Standardized update_summary to always require test name and result
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

    initial begin
        $dumpfile("dump_test_02.vcd"); 
        $dumpvars(0, tb_test_02);
        
        $display("\n=======================================================================");
        $display(" TEST 02: Hardware Flash Reset Pin Validation");
        $display("=======================================================================\n");

        presetn = 0; #33; presetn = 1; @(posedge pclk);
        #10;

        if (FLASH_RST_n === 1'b1) begin
            $display("   [PASS] 1. Default state HIGH.");
        end else begin 
            $display("   [FAIL] 1. Default state not HIGH."); 
            update_summary("tb_test_02", 0); 
            $finish; 
        end

        $display("   [INFO] 2. Pulling Reset LOW via APB...");
        apb_write(32'h00, 32'h0000_0000); 
        #10;
        
        if (FLASH_RST_n === 1'b0) begin
            $display("   [PASS] 2. Reset pulled LOW.");
        end else begin 
            $display("   [FAIL] 2. Failed to pull LOW."); 
            update_summary("tb_test_02", 0); 
            $finish; 
        end

        $display("   [INFO] 3. Restoring Reset HIGH...");
        apb_write(32'h00, 32'h0000_0004); 
        #10;

        if (FLASH_RST_n === 1'b1) begin
            $display("   [PASS] TEST 02 PASSED! Pin behavior verified.\n");
            update_summary("tb_test_02", 1);
        end else begin
            $display("   [FAIL] TEST 02 FAILED!\n");
            update_summary("tb_test_02", 0);
        end

        #100 $finish;
    end
endmodule
