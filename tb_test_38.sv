`timescale 1ns/1ps

// =========================================================================
// TEST 38: AHB Address Remap / Decoder
// =========================================================================
module tb_test_38;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    qspi_apb_master dut (.*);
    
    always #5 pclk = ~pclk;

    task automatic update_summary(input string test_name, input bit pass);
        int fd = $fopen("regression_summary.txt", "a");
        if (fd) begin
            $fdisplay(fd, "%s: %s", test_name, pass ? "PASS" : "FAIL");
            $fclose(fd);
        end
    endtask

    initial begin
        bit captured_err = 0;
        logic [31:0] captured_data = 0;
        
        $dumpfile("dump_test_38.vcd"); $dumpvars(0, tb_test_38);
        $display("\n=======================================================================");
        $display(" TEST 38: AHB Address Remap / Decoder (QSPI-AHB-REG-38)");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);
        
        @(negedge pclk); psel=1; pwrite=0; paddr=32'h1000_0000; pstrb=4'b0000;
        @(negedge pclk); penable=1; 
        
        wait(pready);
        
        // Capture both the slave error flag AND the data bus
        captured_err = pslverr;
        captured_data = prdata;
        
        // Pass if the hardware uses the hard-fault flag (pslverr) OR the silent debug fault code (0x44)
        if (captured_err === 1'b1 || captured_data === 32'h0000_0044) begin 
            $display("   [PASS] Hardware Translation safely rejected out-of-bounds map. (pslverr active OR fault code 0x44 returned).\n");
            update_summary("tb_test_38", 1);
        end else begin 
            $display("   [FAIL] Translation logic failed to assert error on out-of-bounds access. Data returned: %h\n", captured_data);
            update_summary("tb_test_38", 0);
        end

        // Deassert APB bus cleanly
        @(negedge pclk); psel=0; penable=0;

        #100 $finish;
    end
endmodule
