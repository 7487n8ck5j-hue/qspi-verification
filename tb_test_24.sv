`timescale 1ns/1ps

module tb_test24_custom_polling;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    // FIX 1: Use pullups to prevent floating 'X' states on the data bus
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);

    reg slave_D1 = 1'bz; reg slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;

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

    // Simulated Proprietary Flash Response (Bit 7 = Busy Flag)
    initial begin
        logic [7:0] cmd;
        int poll_count = 0;
        forever begin
            @(negedge CS_n);
            for (int i=7; i>=0; i--) begin @(posedge CLK); cmd[i] = (D0 === 1'bz) ? 1'b0 : D0; end
            
            #1; // FIX 2: Hold time offset to clear X state on command interpretation
            
            if (cmd == 8'h70) begin // Custom Proprietary Status Read
                slave_oe = 1;
                for (int i=7; i>=0; i--) begin 
                    @(negedge CLK); 
                    #1; // FIX 2: Delay drive by 1ns to prevent race condition with master sampling
                    // Set Bit 7 HIGH until 4 polls are completed
                    if (i == 7) slave_D1 = (poll_count < 4) ? 1'b1 : 1'b0;
                    else slave_D1 = 1'b0;
                end
                poll_count++;
            end
            @(posedge CS_n); 
            #1; slave_oe = 0; slave_D1 = 1'bz;
        end
    end

    initial begin
        logic [31:0] val = 32'h0000_0080;
        int timeout_ctr = 0;
        
        $dumpfile("dump_test24.vcd"); $dumpvars(0, tb_test24_custom_polling);
        $display("\n=======================================================================");
        $display(" TEST 24: QSPI-PHY-POL-24");
        $display(" Write Completion Custom Polling");
        $display(" Validate support for proprietary flash status registers");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Engaging iterative query cycle on Custom Register (0x70)...");
        
        // FIX 3: Added a timeout limit to the outer polling loop to be safe
        while (val[7] == 1'b1 && timeout_ctr < 50) begin
            apb_write(32'h04, 32'h7000_0000); 
            apb_write(32'h00, 32'h0000_0001); // Start RX
            
            // FIX 3: Replaced infinite wait with a bounded loop
            while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 1000) begin
                @(posedge pclk);
                timeout_ctr++;
            end
            
            apb_read(32'h08, val);
            if (val[7] == 1'b1) $display("   Status Register Bit 7 is HIGH (Busy). Re-issuing query...");
            else $display("   [PASS] Target hardware resolved block. Polling concluded properly.");
        end

        if (timeout_ctr >= 1000) $error("   [FAIL] Hardware locked up. Polling timed out.");

        $display("\nTEST QSPI-PHY-POL-24 COMPLETE.\n");
        #100 $finish;
    end
endmodule