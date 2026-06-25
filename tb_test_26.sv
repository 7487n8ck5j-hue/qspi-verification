`timescale 1ns/1ps

module tb_test26_indac_write;

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

    initial begin
        int timeout_ctr = 0;
        $dumpfile("dump_test26.vcd"); $dumpvars(0, tb_test26_indac_write);
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        for (int i=0; i<8; i++) begin
            apb_write(32'h04, 32'hA1A1_0000 + i); 
        end

        apb_write(32'h00, 32'h0000_0003); // Start TX

        // SAFE WAIT LOOP: Prevents Exit Code 137
        while ((dut.state != 3'd0 || dut.tx_fifo_cnt != 0) && timeout_ctr < 2000) begin
            @(posedge pclk);
            timeout_ctr++;
        end

        if (timeout_ctr >= 2000) $error("   [FAIL] Hardware locked up. Queue did not drain.");
        else if (dut.tx_fifo_cnt == 0) $display("   [PASS] INDAC bulk payload fully transmitted.");

        #100 $finish;
    end
endmodule