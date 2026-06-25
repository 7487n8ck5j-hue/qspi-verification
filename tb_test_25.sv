`timescale 1ns/1ps

module tb_test25_timeout;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    pullup(D3); pullup(D2); pullup(D1); pullup(D0);

    qspi_apb_master dut (.*); // Auto-connects based on names
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
        int timeout_ctr = 0; // BOUNDED TIMEOUT COUNTER
        
        $dumpfile("dump_test25.vcd"); $dumpvars(0, tb_test25_timeout);
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Binding strict transaction expiration limit (0x24)...");
        apb_write(32'h24, 32'h0000_004B); // 75 cycles

        $display("2. Triggering excessively long operation...");
        apb_write(32'h14, 32'h0000_0100); 
        apb_write(32'h00, 32'h0000_0001); 

        // SAFE WAIT LOOP: Prevents Exit Code 137
        while(irq == 1'b0 && timeout_ctr < 1000) begin
            @(posedge pclk);
            timeout_ctr++;
        end

        apb_read(32'h00, val);

        if (timeout_ctr >= 1000) $error("   [FAIL] Simulator timed out. IRQ never asserted.");
        else if (val[12] === 1'b1) $display("   [PASS] Watchdog efficiently terminated operation.");
        else $error("   [FAIL] Expected Timeout Expiration flag. Status unrecorded.");

        #100 $finish;
    end
endmodule