`timescale 1ns/1ps
module tb_test3_polling;
    logic pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; logic [3:0] pstrb = 4'b1111;
    logic rx_dma_ack = 0, tx_dma_ack = 0;
    wire [31:0] prdata; wire pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    
    reg slave_D1 = 1'bz; reg slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;

    qspi_apb_master dut (.*);
    always #5 pclk = ~pclk;

    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; wait(pready);
        @(negedge pclk); psel=0; penable=0;
    endtask

    task automatic apb_read(input [31:0] addr, output logic [31:0] data);
        @(negedge pclk); psel=1; pwrite=0; paddr=addr; pstrb=4'b0000;
        @(negedge pclk); penable=1; wait(pready); data = prdata;
        @(negedge pclk); psel=0; penable=0;
    endtask

    initial begin
        logic [7:0] cmd; int poll_count = 0;
        forever begin
            @(negedge CS_n);
            for (int i=7; i>=0; i--) begin @(posedge CLK); cmd[i] = D0; end
            #1; // Safe hold
            if (cmd == 8'h05) begin
                slave_oe = 1;
                for (int i=7; i>=0; i--) begin 
                    @(negedge CLK); #1; // Prevent race condition
                    if (i == 0) slave_D1 = (poll_count < 3) ? 1'b1 : 1'b0;
                    else slave_D1 = 1'b0;
                end
                poll_count++;
            end
            @(posedge CS_n); #1; slave_oe = 0; slave_D1 = 1'bz;
        end
    end

    initial begin
        logic [31:0] val = 32'h0000_0001; int timeout_ctr = 0;
        $dumpfile("dump_test3.vcd"); $dumpvars(0, tb_test3_polling);
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        while (val[0] == 1'b1 && timeout_ctr < 50) begin
            apb_write(32'h04, 32'h0500_0000); 
            apb_write(32'h00, 32'h0000_0001); // Start RX
            
            while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0)) @(posedge pclk);
            
            apb_read(32'h08, val);
            timeout_ctr++;
        end

        if (val[0] == 1'b0) $display("   [PASS] Flash READY (WIP=0). Auto-polling sequence exited cleanly.");
        else $error("   [FAIL] Timed out waiting for ready.");
        #100 $finish;
    end
endmodule