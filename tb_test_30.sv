`timescale 1ns/1ps

module tb_test30_dac_pred;

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

    // Simulated Quad Predictable Flash Memory
    initial begin
        logic [7:0] cmd;
        forever begin
            @(negedge CS_n);
            for (int i=7; i>=0; i--) begin @(posedge CLK); cmd[i] = (D0 === 1'bz) ? 1'b0 : D0; end
            
            if (cmd == 8'hEB) begin // Continuous mapped read assumption
                #10; slave_oe = 1; 
                for (int i=7; i>=0; i--) begin 
                    @(negedge CLK); slave_drv = (32'hFAC0_FAC0 >> (i*4)) & 4'hF; 
                end
            end
            @(posedge CS_n); slave_oe = 0; slave_drv = 4'bzzzz;
        end
    end

    initial begin
        logic [31:0] val;
        $dumpfile("dump_test30.vcd"); $dumpvars(0, tb_test30_dac_pred);
        $display("\n=======================================================================");
        $display(" TEST 30: QSPI-DAC-PRD-30");
        $display(" DAC Predicted Read Execution");
        $display(" Validate maximum SPI bandwidth");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Engaging structural speed limits for maximum bandwidth...");
        apb_write(32'h0C, 32'h0000_0000); // Division = 0 (Max throughput)
        apb_write(32'h00, 32'h0000_0400); // Engage Quad Output
        apb_write(32'h20, 32'h0000_0001); // Engage XIP/DAC memory map translation

        $display("2. Executing direct read against memory-mapped bounds (0x1000_0000)...");
        apb_read(32'h1000_0000, val);
        wait(dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0); #10;

        if (val === 32'hFAC0_FAC0) 
            $display("   [PASS] Maximum bandwidth fetch stabilized and retrieved cleanly: %h\n", val);
        else 
            $error("   [FAIL] Clock generation fractured at max bandwidth. Payload corrupt.\n");

        $display("TEST QSPI-DAC-PRD-30 COMPLETE.\n");
        #100 $finish;
    end
endmodule