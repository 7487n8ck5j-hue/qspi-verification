`timescale 1ns/1ps

module tb_test5_xip;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    logic [3:0] slave_drv = 4'hz; logic slave_oe = 0;
    assign D3 = slave_oe ? slave_drv[3] : 1'bz;
    assign D2 = slave_oe ? slave_drv[2] : 1'bz;
    assign D1 = slave_oe ? slave_drv[1] : 1'bz;
    assign D0 = slave_oe ? slave_drv[0] : 1'bz;

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

    task automatic apb_read(input [31:0] addr, output logic [31:0] data);
        @(negedge pclk); psel=1; pwrite=0; paddr=addr; pstrb=4'b0000;
        @(negedge pclk); penable=1; wait(pready);
        data = prdata;
        @(negedge pclk); psel=0; penable=0;
    endtask

    // Simulated Quad Data Provider
    initial begin
        logic [7:0] cmd;
        forever begin
            @(negedge CS_n);
            for (int i=7; i>=0; i--) begin @(posedge CLK); cmd[i] = (D0 === 1'bz) ? 1'b0 : D0; end
            if (cmd == 8'hEB) begin
                #30; slave_oe = 1; 
                for (int i=7; i>=0; i--) begin 
                    @(negedge CLK); slave_drv = (32'h1A57_8C73 >> (i*4)) & 4'hF; 
                end
            end
            @(posedge CS_n); slave_oe = 0; slave_drv = 4'bzzzz;
        end
    end

    initial begin
        logic [31:0] val;
        $dumpfile("dump_test5.vcd"); $dumpvars(0, tb_test5_xip);
        $display("\n=======================================================================");
        $display(" TEST 5: QSPI-DAC-XIP-05");
        $display(" BOOT Feature in Quad XIP Mode");
        $display(" Validate automated high-speed boot configuration.");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Translating AHB execution limits to XIP...");
        apb_write(32'h20, 32'h0000_0001); // XIP Enable
        apb_write(32'h00, 32'h0000_0400); // Quad Enable

        $display("2. Executing direct memory map fetch at Boot vector 0x1000_0000...");
        apb_read(32'h1000_0000, val);
        
        wait(dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0); #10;

        if (val === 32'h1A57_8C73) $display("   [PASS] High-Speed Quad Boot Instruction Fetched: %h\n", val);
        else $error("   [FAIL] Expected 1A578C73, Got: %h\n", val);

        $display("TEST QSPI-DAC-XIP-05 COMPLETE.\n");
        #100 $finish;
    end
endmodule