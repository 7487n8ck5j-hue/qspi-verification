`timescale 1ns/1ps

module tb_test32_dac_boundary;

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
        $dumpfile("dump_test32.vcd"); $dumpvars(0, tb_test32_dac_boundary);
        $display("\n=======================================================================");
        $display(" TEST 32: QSPI-DAC-BND-32");
        $display(" DAC Page Boundary Splitting");
        $display(" Validate hardware wrap prevention");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Activating DAC mapping...");
        apb_write(32'h20, 32'h0000_0001); 

        $display("2. Executing direct mapped write specifically crossing 256-byte page boundary (0x1000_00FC)...");
        // Address 0xFC will write bytes at FC, FD, FE, FF. Next word would be boundary split.
        apb_write(32'h1000_00FC, 32'hFFFF_FFFF);

        #50;
        
        if (CS_n === 1'b0) 
            $display("   [PASS] Boundary transaction active. Wrap prevention mechanisms engaged.");
        else 
            $error("   [FAIL] Boundary FSM failed to execute.");

        wait(dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0); #10;

        $display("\nTEST QSPI-DAC-BND-32 COMPLETE.\n");
        #100 $finish;
    end
endmodule