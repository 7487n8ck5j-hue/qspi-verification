`timescale 1ns/1ps

module tb_test2_reset;

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
        .paddr(paddr), .pwdata(pwdata), .pstrb(pstrb), 
        .prdata(prdata), .pready(pready), .pslverr(pslverr), .irq(irq),
        .rx_dma_req(rx_dma_req), .rx_dma_ack(rx_dma_ack), 
        .tx_dma_req(tx_dma_req), .tx_dma_ack(tx_dma_ack),
        .CS_n(CS_n), .CLK(CLK), .FLASH_RST_n(FLASH_RST_n),
        .D3(D3), .D2(D2), .D1(D1), .D0(D0)
    );

    always #5 pclk = ~pclk;

    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; wait(pready);
        @(negedge pclk); psel=0; penable=0;
    endtask

    initial begin
        $dumpfile("dump_test2.vcd"); $dumpvars(0, tb_test2_reset);
        $display("\n--- Starting Test 2: Hardware Flash Reset ---");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        #10;
        if (FLASH_RST_n === 1'b1) $display("1. Default State is HIGH (Correct)");
        else $error("1. Default State FAILED");

        $display("2. Pulling Reset LOW via APB...");
        apb_write(32'h00, 32'h0000_0000); // Clear Bit 2
        #10;
        if (FLASH_RST_n === 1'b0) $display("   Reset successfully pulled LOW.");
        else $error("   Failed to pull Reset LOW.");

        $display("3. Restoring Reset HIGH...");
        apb_write(32'h00, 32'h0000_0004); // Set Bit 2
        #10;
        if (FLASH_RST_n === 1'b1) $display("TEST 2 PASSED! Pin behavior verified.");
        else $error("TEST 2 FAILED!");

        #100 $finish;
    end
endmodule
