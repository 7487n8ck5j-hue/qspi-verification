`timescale 1ns/1ps

module tb_test18_stig_bank;

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

    // Simulating continuous data generation for 3 back-to-back word transfers
    initial begin
        forever begin
            @(negedge CS_n);
            slave_oe = 1;
            for (int i=31; i>=0; i--) begin @(negedge CLK); slave_D1 = (32'h1111_1111 >> i) & 1'b1; end
            for (int i=31; i>=0; i--) begin @(negedge CLK); slave_D1 = (32'h2222_2222 >> i) & 1'b1; end
            for (int i=31; i>=0; i--) begin @(negedge CLK); slave_D1 = (32'h3333_3333 >> i) & 1'b1; end
            @(posedge CS_n); slave_oe = 0;
        end
    end

    initial begin
        $dumpfile("dump_test18.vcd"); $dumpvars(0, tb_test18_stig_bank);
        $display("\n=======================================================================");
        $display(" TEST 18: QSPI-APB-SRD-18");
        $display(" STIG Memory Bank");
        $display(" Validate extended read transfers (>8 Bytes)");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Initiating extended transfer sequence (3 words / 12 bytes)...");
        // Issue 3 consecutive Start commands before clearing the buffer
        apb_write(32'h00, 32'h0000_0001); 
        wait(dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0);
        apb_write(32'h00, 32'h0000_0001); 
        wait(dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0);
        apb_write(32'h00, 32'h0000_0001); 
        wait(dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0);

        $display("2. Checking RX FIFO Depth...");
        #10;
        if (dut.rx_fifo_cnt == 4'd3) 
            $display("   [PASS] Extended >8 byte transfer accumulated correctly in memory bank.\n");
        else 
            $error("   [FAIL] Internal queue did not hold expected depth. Got: %d\n", dut.rx_fifo_cnt);

        $display("TEST QSPI-APB-SRD-18 COMPLETE.\n");
        #100 $finish;
    end
endmodule