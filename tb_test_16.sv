`timescale 1ns/1ps

module tb_test16_hw_rst;

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
        $dumpfile("dump_test16.vcd"); $dumpvars(0, tb_test16_hw_rst);
        $display("\n=======================================================================");
        $display(" TEST 16: QSPI-PHY-RST-16");
        $display(" Hardware Reset Pin Routing");
        $display(" Validate dedicated target reset signals.");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Checking default pin state (Expected: HIGH)...");
        #10;
        if (FLASH_RST_n === 1'b1) $display("   [PASS] Default reset state is unasserted (HIGH).");
        else $error("   [FAIL] Default reset state is asserted or floating.");

        $display("2. Activating physical hardware reset via CTRL_REG Bit 2...");
        // Clear Bit 2 to pull FLASH_RST_n LOW
        apb_write(32'h00, 32'h0000_0000); 
        #20;
        
        if (FLASH_RST_n === 1'b0) $display("   [PASS] FLASH_RST_n safely pulled LOW to reset external device.");
        else $error("   [FAIL] FLASH_RST_n did not respond to control register.");

        $display("3. Releasing physical hardware reset...");
        // Set Bit 2 to return FLASH_RST_n HIGH
        apb_write(32'h00, 32'h0000_0004); 
        #20;

        if (FLASH_RST_n === 1'b1) $display("   [PASS] FLASH_RST_n successfully released to HIGH.\n");
        else $error("   [FAIL] FLASH_RST_n remained stuck LOW.\n");

        $display("TEST QSPI-PHY-RST-16 COMPLETE.\n");
        #100 $finish;
    end
endmodule