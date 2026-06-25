`timescale 1ns/1ps

module tb_test9_dma_rx;

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

    // Simulated SPI flash device response logic
    initial begin
        forever begin
            @(negedge CS_n);
            if (dut.ctrl_reg[1] == 1'b0) begin
                slave_oe = 1;
                for (int i=31; i>=0; i--) begin
                    @(negedge CLK);
                    slave_D1 = 1'b1;
                end
            end
            @(posedge CS_n); slave_oe = 0;
        end
    end

    initial begin
        $dumpfile("dump_test9.vcd"); $dumpvars(0, tb_test9_dma_rx);
        $display("\n--- Starting Test 9: RX FIFO Watermark (DMA Request) ---");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        // Configure RX Watermark to 1 (Bits 23:16 = 0x01), Enable RX DMA (Bit 1 = 1) -> 0x0001_0002
        $display("1. Programming RX DMA Watermark to 1...");
        apb_write(32'h28, 32'h0001_0002);

        $display("2. Launching RX transaction map sequence...");
        apb_write(32'h00, 32'h0000_0001); // RX Mode + Start trigger

        $display("3. Monitoring interface for RX DMA handshake initiation...");
        wait(rx_dma_req == 1'b1);
        $display("   Hardware Asserted rx_dma_req! Simulating DMA drain handshake...");

        @(negedge pclk);
        rx_dma_ack = 1'b1;
        @(negedge pclk);
        rx_dma_ack = 1'b0;

        #10;
        if (rx_dma_req == 1'b0) $display("TEST 9 PASSED! Handshake cleanly drained and lowered lines.");
        else $error("TEST 9 FAILED! Line remains trapped high.");

        #100 $finish;
    end
endmodule
