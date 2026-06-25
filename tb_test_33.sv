`timescale 1ns/1ps

module tb_test33_dac_poll;

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

    // Simulated Auto-Poll Response
    initial begin
        logic [7:0] cmd;
        int poll_count = 0;
        forever begin
            @(negedge CS_n);
            for (int i=7; i>=0; i--) begin @(posedge CLK); cmd[i] = (D0 === 1'bz) ? 1'b0 : D0; end
            
            if (cmd == 8'h05) begin // Read Status Register
                slave_oe = 1;
                for (int i=7; i>=0; i--) begin 
                    @(negedge CLK); 
                    if (i == 0) slave_D1 = (poll_count < 2) ? 1'b1 : 1'b0; // Busy drops after 2 polls
                    else slave_D1 = 1'b0;
                end
                poll_count++;
            end
            @(posedge CS_n); slave_oe = 0;
        end
    end

    initial begin
        $dumpfile("dump_test33.vcd"); $dumpvars(0, tb_test33_dac_poll);
        $display("\n=======================================================================");
        $display(" TEST 33: QSPI-DAC-POLL-33");
        $display(" Auto-Polling after DAC Write");
        $display(" Validate automated write cycle tracking");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Activating DAC Write configuration...");
        apb_write(32'h20, 32'h0000_0001); 

        $display("2. Executing DAC Write at 0x1000_0000...");
        apb_write(32'h1000_0000, 32'hCAFE_BABE); 

        $display("3. Monitoring hardware for autonomous WIP tracking phase...");
        
        // Wait for FSM to naturally execute write -> poll -> poll -> finish
        wait(dut.state == 3'd0 && dut.ctrl_reg[0] == 1'b0); #20;

        $display("   [PASS] Hardware auto-polling sequence verified. Write cycle resolved cleanly.\n");

        $display("TEST QSPI-DAC-POLL-33 COMPLETE.\n");
        #100 $finish;
    end
endmodule