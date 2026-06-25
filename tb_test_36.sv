`timescale 1ns/1ps

module tb_test36_pipeline;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    // Fix for Red 'X' floating states
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);

    qspi_apb_master dut (.*);

    always #5 pclk = ~pclk;

    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; 
        if (!pready) $error("   [FAIL] Zero-Wait-State violated! pready dropped.");
        wait(pready);
        @(negedge pclk); psel=0; penable=0;
    endtask

    initial begin
        int timeout_ctr = 0;
        $dumpfile("dump_test36.vcd"); $dumpvars(0, tb_test36_pipeline);
        $display("\n=======================================================================");
        $display(" TEST 36: QSPI-PHY-BST-36");
        $display(" PHY Pipeline Mode (Zero-Wait-State)");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Initiating pipelined APB burst write to TX FIFO...");
        apb_write(32'h04, 32'h1111_1111);
        apb_write(32'h04, 32'h2222_2222);
        apb_write(32'h04, 32'h3333_3333);
        apb_write(32'h04, 32'h4444_4444);

        $display("   [PASS] Pipelined APB writes completed.");
        apb_write(32'h00, 32'h0000_0003); // Start TX

        // Bounded loop to prevent Exit Code 137
        while ((dut.state != 3'd0 || dut.tx_fifo_cnt != 0) && timeout_ctr < 1000) begin
            @(posedge pclk);
            timeout_ctr++;
        end
        
        if (timeout_ctr < 1000) $display("   [PASS] Transmission executed seamlessly.\n");
        else $error("   [FAIL] FSM Locked up during pipeline transmission.\n");

        $display("TEST QSPI-PHY-BST-36 COMPLETE.\n");
        #100 $finish;
    end
endmodule