`timescale 1ns/1ps

module tb_test37_ddr_dspi;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    
    reg [3:0] slave_drv = 4'hz; 
    reg slave_oe = 0;
    assign D3 = slave_oe ? slave_drv[3] : 1'bz;
    assign D2 = slave_oe ? slave_drv[2] : 1'bz;
    assign D1 = slave_oe ? slave_drv[1] : 1'bz;
    assign D0 = slave_oe ? slave_drv[0] : 1'bz;

    qspi_apb_master dut (.*);
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

    // Mock Flash for Quad RX (With #1 delays to fix race conditions)
    initial begin
        reg [31:0] payload = 32'hD5D5_5D5D;
        forever begin
            @(negedge CS_n);
            #1; slave_oe = 1; 
            for (int i=7; i>=0; i--) begin 
                @(negedge CLK); 
                #1; // Wait 1ns after clock edge to drive data
                slave_drv = payload[(i*4) +: 4]; 
            end
            @(posedge CS_n); 
            #1; slave_oe = 0; slave_drv = 4'bzzzz;
        end
    end

    initial begin
        logic [31:0] val; int timeout_ctr = 0;
        $dumpfile("dump_test37.vcd"); $dumpvars(0, tb_test37_ddr_dspi);
        $display("\n=======================================================================");
        $display(" TEST 37: QSPI-DDR-DSPI-37");
        $display(" DSPI / OSPI Quad/DDR Protocol Mode");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        apb_write(32'h00, 32'h0000_0401); // Quad Enable (Bit 10) + Start RX
        
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 1000) begin
            @(posedge pclk); timeout_ctr++;
        end

        apb_read(32'h08, val);
        if (val === 32'hD5D5_5D5D) $display("   [PASS] Multi-Lane payload captured successfully: %h\n", val);
        else $error("   [FAIL] Data corruption. Got: %h\n", val);

        $display("TEST QSPI-DDR-DSPI-37 COMPLETE.\n");
        #100 $finish;
    end
endmodule