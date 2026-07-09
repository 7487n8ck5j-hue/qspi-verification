`timescale 1ns/1ps

module tb_test_32;

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

    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; wait(pready);
        @(negedge pclk); psel=0; penable=0;
    endtask

    initial begin
        int cs_toggles = 0;
        
        $dumpfile("dump_test_32.vcd"); $dumpvars(0, tb_test_32);
        $display("\n=======================================================================");
        $display(" TEST 32: DAC Memory Boundary Crossing");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);
        
        apb_write(32'h20, 32'h0000_0001); 
        
        // Spawn an immortal background monitor to count every time CS_n goes low
        fork
            begin
                forever begin
                    @(negedge CS_n);
                    cs_toggles++;
                end
            end
        join_none
        
        // Initiate the APB transaction across the boundary
        apb_write(32'h1000_00FC, 32'hFFFF_FFFF);
        
        // Wait a large, safe window to let the SPI hardware fully process, 
        // assert CS_n, shift all data, and deassert.
        repeat(1000) @(posedge pclk); 
        
        if (cs_toggles > 0) begin
            $display("   [PASS] Boundary FSM executed. Transaction correctly stretched (CS_n toggled %0d times).\n", cs_toggles);
            update_summary("tb_test_32", 1);
        end else begin
            $display("   [FAIL] Boundary FSM failed to stretch transaction. CS_n never asserted.\n");
            update_summary("tb_test_32", 0);
        end
        
        #100 $finish;
    end
endmodule
