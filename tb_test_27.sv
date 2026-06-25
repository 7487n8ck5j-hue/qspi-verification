`timescale 1ns/1ps

module tb_test27_indac_read;

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

    task automatic apb_read(input [31:0] addr, output logic [31:0] data);
        @(negedge pclk); psel=1; pwrite=0; paddr=addr; pstrb=4'b0000;
        @(negedge pclk); penable=1; wait(pready);
        data = prdata;
        @(negedge pclk); psel=0; penable=0;
    endtask

    // Simulated Flash feeding continuous bulk data
    initial begin
        forever begin
            @(negedge CS_n);
            slave_oe = 1;
            // Send 3 words back to back
            for (int w=0; w<3; w++) begin
                for (int i=31; i>=0; i--) begin 
                    @(negedge CLK); slave_D1 = ((32'h1000_1000 + w) >> i) & 1'b1; 
                end
            end
            @(posedge CS_n); slave_oe = 0;
        end
    end

    initial begin
        logic [31:0] val;
        $dumpfile("dump_test27.vcd"); $dumpvars(0, tb_test27_indac_read);
        $display("\n=======================================================================");
        $display(" TEST 27: QSPI-IND-SRD-27");
        $display(" INDAC Bulk Read via SRAM");
        $display(" Validate indirect bulk read transfers");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Launching continuous bulk read command...");
        // Re-triggering RX 3 times quickly to queue up consecutive reads
        apb_write(32'h00, 32'h0000_0001); 
        wait(dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0);
        apb_write(32'h00, 32'h0000_0001); 
        wait(dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0);
        apb_write(32'h00, 32'h0000_0001); 
        wait(dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0);

        $display("2. Flushing internal SRAM / RX FIFO logic...");
        apb_read(32'h08, val); // Pop Word 1
        if (val === 32'h1000_1000) $display("   [PASS] Word 1 accurately fetched: %h", val);
        else $error("   [FAIL] Word 1 Mismatch: %h", val);

        apb_read(32'h08, val); // Pop Word 2
        if (val === 32'h1000_1001) $display("   [PASS] Word 2 accurately fetched: %h", val);
        else $error("   [FAIL] Word 2 Mismatch: %h", val);

        $display("\nTEST QSPI-IND-SRD-27 COMPLETE.\n");
        #100 $finish;
    end
endmodulee