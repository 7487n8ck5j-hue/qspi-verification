`timescale 1ns/1ps

module tb_test38_ahb_remap;

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

    initial begin
        $dumpfile("dump_test38.vcd"); $dumpvars(0, tb_test38_ahb_remap);
        $display("\n=======================================================================");
        $display(" TEST 38: QSPI-AHB-REG-38");
        $display(" AHB Address Remapping Boundary Protection");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Executing APB mapped read targeting 0x1000_0000 range...");
        @(negedge pclk); psel=1; pwrite=0; paddr=32'h1000_0000; pstrb=4'b0000;
        @(negedge pclk); penable=1; 
        
        #1; // Delay to let combinational logic resolve pslverr
        if (pslverr) $display("   [PASS] Hardware Translation safely rejected out-of-bounds map. pslverr active.\n");
        else $error("   [FAIL] Translation logic failed to assert error.\n");

        @(negedge pclk); psel=0; penable=0;

        $display("TEST QSPI-AHB-REG-38 COMPLETE.\n");
        #100 $finish;
    end
endmodule