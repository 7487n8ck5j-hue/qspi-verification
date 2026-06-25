`timescale 1ns/1ps

module tb_test4_fifo;

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
        $dumpfile("dump_test4.vcd"); $dumpvars(0, tb_test4_fifo);
        $display("\n=======================================================================");
        $display(" TEST 4: QSPI-APB-LVL-04");
        $display(" Legacy SPI Mode FIFO Thresholds");
        $display(" Validate raw SPI fallback and manual FIFO interrupts");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Programming DMA/FIFO TX Thresholds to Level 2...");
        // TX Threshold = 2 (Bits 15:8 = 0x02), Enable TX Reqs (Bit 0 = 1) -> 0x0000_0201
        apb_write(32'h28, 32'h0000_0201); 

        $display("2. Manually pushing 4 words into Legacy TX FIFO...");
        for (int i=0; i<4; i++) begin
            apb_write(32'h04, 32'hA0A0_0000);
        end

        #10;
        if (tx_dma_req === 1'b0) $display("   Status: Queue safely loaded. Request pin Low.");
        else $error("   [FAIL] Interrupt/Request triggered too early.");

        $display("3. Activating Transfer. Monitoring for automated queue drainage...");
        apb_write(32'h00, 32'h0000_0003); // Start TX

        wait(tx_dma_req == 1'b1);
        $display("   [PASS] Level thresholds successfully triggered raw DMA/FIFO request.\n");

        $display("TEST QSPI-APB-LVL-04 COMPLETE.\n");
        #100 $finish;
    end
endmodule