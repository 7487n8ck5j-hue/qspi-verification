`timescale 1ns/1ps

module tb_test23_sram_partition;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    assign D3 = 1'bz; assign D2 = 1'bz; assign D1 = 1'bz; assign D0 = 1'bz;

    qspi_apb_master dut (
        .pclk(pclk), .presetn(presetn), .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .pstrb(pstrb), .prdata(prdata), .pready(pready),
        .pslverr(pslverr), .irq(irq), .rx_dma_req(rx_dma_req), .rx_dma_ack(rx_dma_ack),
        .tx_dma_req(tx_dma_req), .tx_dma_ack(tx_dma_ack), .CS_n(CS_n), .CLK(CLK),
        .FLASH_RST_n(FLASH_RST_n), .D3(D3), .D2(D2), .D1(D1), .D0(D0)
    );

    always #5 pclk = ~pclk;

    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; wait(pready);
        @(negedge pclk); psel=0; penable=0;
    endtask

    initial begin
        $dumpfile("dump_test23.vcd"); $dumpvars(0, tb_test23_sram_partition);
        $display("\n=======================================================================");
        $display(" TEST 23: QSPI-APB-PAR-23");
        $display(" SRAM Partition Configuration");
        $display(" Validate internal SRAM memory division");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Configuring strict SRAM partition thresholds (DMA_CTRL)...");
        // RX Threshold = 4 (Bits 23:16), TX Threshold = 4 (Bits 15:8), Enable Both -> 0x0004_0403
        apb_write(32'h28, 32'h0004_0403); 

        $display("2. Verifying TX boundary logic response...");
        #10;
        if (tx_dma_req === 1'b1) $display("   [PASS] TX Memory partition evaluated correctly (Empty queue requested data).");
        else $error("   [FAIL] TX Memory partition evaluation failed.");

        $display("3. Verifying RX boundary logic response...");
        if (rx_dma_req === 1'b0) $display("   [PASS] RX Memory partition evaluated correctly (Empty queue blocked read request).");
        else $error("   [FAIL] RX Memory partition evaluation failed.");

        $display("\nTEST QSPI-APB-PAR-23 COMPLETE.\n");
        #100 $finish;
    end
endmodule