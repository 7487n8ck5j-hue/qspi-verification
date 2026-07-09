`timescale 1ns/1ps

// =========================================================================
// TEST 04: Legacy SPI Mode FIFO Thresholds (TX)
// =========================================================================
module tb_test_04;

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

    // FIX: Standardized task signature
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
        $dumpfile("dump_test_04.vcd"); $dumpvars(0, tb_test_04);
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        apb_write(32'h28, 32'h0000_0201); 
        for (int i=0; i<3; i++) begin
            apb_write(32'h04, 32'hA0A0_0000);
        end

        #10;
        if (tx_dma_req !== 1'b0) begin
            $display("   [FAIL] Interrupt triggered too early.");
            update_summary("tb_test_04", 0);
            $finish;
        end

        apb_write(32'h00, 32'h0000_0003); // Start TX

        fork
            begin
                wait(tx_dma_req == 1'b1);
                $display("   [PASS] Level thresholds successfully triggered.");
                update_summary("tb_test_04", 1);
            end
            begin
                #2000;
                $display("   [FAIL] Timeout: TX threshold request never triggered.");
                update_summary("tb_test_04", 0);
            end
        join_any
        disable fork;

        #100 $finish;
    end
endmodule
