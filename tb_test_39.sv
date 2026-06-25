`timescale 1ns/1ps

module tb_test39_overrun;

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

    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; wait(pready);
        @(negedge pclk); psel=0; penable=0;
    endtask

    task automatic apb_read(input [31:0] addr, output logic [31:0] data);
        @(negedge pclk); psel=1; pwrite=0; paddr=addr; pstrb=4'b0000;
        @(negedge pclk); penable=1; wait(pready);
        data = prdata;
        @(negedge pclk); psel=0; penable=0;
    endtask

    initial begin
        logic [31:0] val;
        $dumpfile("dump_test39.vcd"); $dumpvars(0, tb_test39_overrun);
        $display("\n=======================================================================");
        $display(" TEST 39: QSPI-IND-LVL-39");
        $display(" SRAM Overrun / Back-Pressure Handling");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Pushing 10 words into the 8-word TX FIFO...");
        for (int i=0; i<10; i++) begin
            apb_write(32'h04, 32'hA1A1_A1A1); 
        end

        apb_read(32'h00, val);

        if (dut.tx_fifo_cnt == 4'd8 && val[5] == 1'b1) 
            $display("   [PASS] Hardware throttled queue at 8. TX_Full flag successfully asserted.\n");
        else 
            $error("   [FAIL] Hardware failed to clamp queue size.\n");

        $display("TEST QSPI-IND-LVL-39 COMPLETE.\n");
        #100 $finish;
    end
endmodule