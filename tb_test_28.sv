`timescale 1ns/1ps

module tb_test28_int_mask;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    // FIX 1: Use pullups instead of 1'bz to prevent Red 'X' states propagating into the FSM
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);

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
    endtask // FIX 2: Corrected 'taskend' to 'endtask'

    task automatic apb_read(input [31:0] addr, output logic [31:0] data);
        @(negedge pclk); psel=1; pwrite=0; paddr=addr; pstrb=4'b0000;
        @(negedge pclk); penable=1; wait(pready);
        data = prdata;
        @(negedge pclk); psel=0; penable=0;
    endtask

    // Added a minimal mock flash response to ensure the FSM doesn't ingest 'X' states
    reg slave_D1 = 1'bz; reg slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;

    initial begin
        forever begin
            @(negedge CS_n);
            #1; slave_oe = 1;
            for (int i=31; i>=0; i--) begin 
                @(negedge CLK); #1; slave_D1 = 1'b1; 
            end
            @(posedge CS_n); #1; slave_oe = 0; slave_D1 = 1'bz;
        end
    end

    initial begin
        logic [31:0] val;
        int timeout_ctr = 0; // FIX 3: Initialize a timeout tracker
        
        $dumpfile("dump_test28.vcd"); $dumpvars(0, tb_test28_int_mask);
        $display("\n--- Starting Test 28: Interrupt Masking ---");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Launching RX Transfer with IntEn (Bit 3) explicitly cleared to 0...");
        // Start (Bit 0) = 1, Dir RX (Bit 1) = 0, IntEn (Bit 3) = 0 -> 0x0000_0001
        apb_write(32'h00, 32'h0000_0001);

        $display("2. Waiting for FSM transfer completion sequence...");
        
        // FIX 4: Replace infinite wait() with a bounded timeout loop
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 1000) begin
            @(posedge pclk);
            timeout_ctr++;
        end

        if (timeout_ctr >= 1000) begin
            $error("   [FAIL] Hardware locked up. Bounded timeout reached.");
        end

        #10;

        $display("3. Validating external physical pin masking...");
        if (irq === 1'b1) $error("   FAILED! Physical irq pin went high despite IntEn mask.");
        else $display("   PASSED! Pin remained low.");

        $display("4. Checking if internal logging updated normally...");
        apb_read(32'h00, val);
        if (val[4] === 1'b1) $display("TEST 28 PASSED! Internal complete bit logged properly under mask condition.\n");
        else $error("TEST 28 FAILED! Status register did not set complete bit.");

        #100 $finish;
    end
endmodule