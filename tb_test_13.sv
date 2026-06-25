`timescale 1ns/1ps

module tb_test13_por;

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

    task automatic apb_read(input [31:0] addr, output logic [31:0] data);
        @(negedge pclk); psel=1; pwrite=0; paddr=addr; pstrb=4'b0000;
        @(negedge pclk); penable=1; wait(pready);
        data = prdata;
        @(negedge pclk); psel=0; penable=0;
    endtask

    initial begin
        logic [31:0] val;
        $dumpfile("dump_test13.vcd"); $dumpvars(0, tb_test13_por);
        $display("\n=======================================================================");
        $display(" TEST 13: QSPI-APB-RST-13");
        $display(" APB Register POR Default Validation");
        $display(" Validate Power-On Reset (POR) register states.");
        $display("=======================================================================\n");
        
        $display("1. Asserting and de-asserting hardware presetn...");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("2. Checking architectural defaults...");
        
        apb_read(32'h00, val);
        if (val === 32'h0000_0044) $display("   [PASS] CTRL_REG (0x00) POR is 0x0000_0044");
        else $error("   [FAIL] CTRL_REG POR Mismatch! Got: %h", val);

        apb_read(32'h14, val);
        if (val === 32'h0000_0000) $display("   [PASS] DUMMY_CTRL (0x14) POR is 0x0000_0000");
        else $error("   [FAIL] DUMMY_CTRL POR Mismatch! Got: %h", val);

        apb_read(32'h24, val);
        if (val === 32'h0000_0000) $display("   [PASS] TIMEOUT_CTRL (0x24) POR is 0x0000_0000");
        else $error("   [FAIL] TIMEOUT_CTRL POR Mismatch! Got: %h", val);

        apb_read(32'h28, val);
        if (val === 32'h0000_0000) $display("   [PASS] DMA_CTRL (0x28) POR is 0x0000_0000");
        else $error("   [FAIL] DMA_CTRL POR Mismatch! Got: %h", val);

        $display("\nTEST QSPI-APB-RST-13 COMPLETE.\n");
        #100 $finish;
    end
endmodule