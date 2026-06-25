`timescale 1ns/1ps

module tb_test29_dma_hsk;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    logic slave_D1 = 1'bz; logic slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;
    assign D3 = 1'bz; assign D2 = 1'bz; assign D0 = 1'bz;

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

    // Simulated Fast Flash
    initial begin
        forever begin
            @(negedge CS_n);
            slave_oe = 1;
            for (int i=31; i>=0; i--) begin @(negedge CLK); slave_D1 = 1'b1; end
            @(posedge CS_n); slave_oe = 0;
        end
    end

    initial begin
        $dumpfile("dump_test29.vcd"); $dumpvars(0, tb_test29_dma_hsk);
        $display("\n=======================================================================");
        $display(" TEST 29: QSPI-DMA-HSK-29");
        $display(" DMA Peripheral Handshaking (Read/Write)");
        $display(" Validate AXI-like DMA integration");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Configuring DMA boundaries: RX Threshold = 1, TX Threshold = 1...");
        // RX Thresh=1 (Bits 23:16), TX Thresh=1 (Bits 15:8), En TX/RX = 1 -> 0x0001_0103
        apb_write(32'h28, 32'h0001_0103); 

        // --- TX Handshake Test ---
        $display("2. Validating TX Handshake integration...");
        wait(tx_dma_req == 1'b1);
        $display("   [PASS] TX DMA Request raised automatically.");
        
        @(negedge pclk); tx_dma_ack = 1'b1; // System pushes data
        @(negedge pclk); tx_dma_ack = 1'b0; 
        #10;
        
        if (dut.tx_fifo_cnt == 4'd1) $display("   [PASS] TX Acknowledge successfully populated FIFO.");
        else $error("   [FAIL] TX Acknowledge failed.");

        // --- RX Handshake Test ---
        $display("3. Validating RX Handshake integration...");
        apb_write(32'h00, 32'h0000_0001); // Start RX
        wait(dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0); // Wait for flash to feed RX FIFO
        
        wait(rx_dma_req == 1'b1);
        $display("   [PASS] RX DMA Request raised automatically after payload receipt.");
        
        @(negedge pclk); rx_dma_ack = 1'b1; // System pops data
        @(negedge pclk); rx_dma_ack = 1'b0; 
        #10;

        if (dut.rx_fifo_cnt == 4'd0) $display("   [PASS] RX Acknowledge successfully drained FIFO.\n");
        else $error("   [FAIL] RX Acknowledge failed.");

        $display("TEST QSPI-DMA-HSK-29 COMPLETE.\n");
        #100 $finish;
    end
endmodule