`timescale 1ns/1ps

module tb_test40_hold_suspend;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    // CRITICAL: Pullups represent physical PCB traces holding unused pins High
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);

    qspi_apb_master dut (.*);

    always #5 pclk = ~pclk;

    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; wait(pready);
        @(negedge pclk); psel=0; penable=0;
    endtask

    initial begin
        int timeout_ctr = 0;
        $dumpfile("dump_test40.vcd"); $dumpvars(0, tb_test40_hold_suspend);
        $display("\n=======================================================================");
        $display(" TEST 40: QSPI-PHY-HSK-40");
        $display(" Hardware HOLD Pin Suspension");
        $display("=======================================================================\n");
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        apb_write(32'h04, 32'h1234_5678); 
        apb_write(32'h00, 32'h0000_0003); // Start TX in SINGLE Mode (Quad is OFF)

        #20; 

        if (CS_n === 1'b0) begin
            if (D3 === 1'b1) 
                $display("   [PASS] D3 (HOLD_n) safely floating High-Z / Pulled HIGH.");
            else 
                $error("   [FAIL] D3 driven LOW! Transaction illegally suspended.");
        end else $error("   [FAIL] FSM failed to start.");

        // Bounded loop
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 1000) begin
            @(posedge pclk); timeout_ctr++;
        end

        $display("\nTEST QSPI-PHY-HSK-40 COMPLETE.\n");
        #100 $finish;
    end
endmodule