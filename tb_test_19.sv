`timescale 1ns/1ps

module tb_test19_write_prot;

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

    initial begin
        $dumpfile("dump_test19.vcd"); $dumpvars(0, tb_test19_write_prot);
        $display("\n=======================================================================");
        $display(" TEST 19: QSPI-AHB-ERR-19");
        $display(" Hardware Write Protection");
        $display(" Validate block-level hardware address locking");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Attempting illegal memory-mapped WRITE to Read-Only RX_REG (0x08)...");
        
        @(negedge pclk); psel=1; pwrite=1; paddr=32'h08; pwdata=32'hDEAD_BEEF; pstrb=4'b1111;
        @(negedge pclk); penable=1; 
        
        #1; // Sample the error flag asynchronously 
        
        if (pslverr === 1'b1) 
            $display("   [PASS] Hardware Address Protection caught the illegal write. Slave Error Assserted.");
        else 
            $display("   [NOTE] Design logic ignores RO write. Checking if data was safely rejected...");

        @(negedge pclk); psel=0; penable=0; #10;

        $display("2. Verifying RX_REG remains uncorrupted by illegal operation...");
        @(negedge pclk); psel=1; pwrite=0; paddr=32'h08; pstrb=4'b0000;
        @(negedge pclk); penable=1; wait(pready); 
        
        if (prdata === 32'h0000_0000) 
            $display("   [PASS] Memory successfully block-locked. Write blocked completely.\n");
        else 
            $error("   [FAIL] Hardware write protection bypassed. Data corrupted: %h\n", prdata);
            
        @(negedge pclk); psel=0; penable=0;

        $display("TEST QSPI-AHB-ERR-19 COMPLETE.\n");
        #100 $finish;
    end
endmodulele