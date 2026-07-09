`timescale 1ns/1ps

// =========================================================================
// TEST 09: DDR Protocol Parameters Synchronization
// =========================================================================
module tb_test_09;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    pullup(D3); pullup(D2); pullup(D1); pullup(D0);

    reg [3:0] slave_drv = 4'b0000; 
    logic slave_oe = 0;
    assign D3 = slave_oe ? slave_drv[3] : 1'bz;
    assign D2 = slave_oe ? slave_drv[2] : 1'bz;
    assign D1 = slave_oe ? slave_drv[1] : 1'bz;
    assign D0 = slave_oe ? slave_drv[0] : 1'bz;

    qspi_apb_master dut (.*);
    always #5 pclk = ~pclk;

    // Standardized task signature for Makefile tracking
    task automatic update_summary(input string test_name, input bit pass);
        int fd = $fopen("regression_summary.txt", "a");
        if (fd) begin
            $fdisplay(fd, "%s: %s", test_name, pass ? "PASS" : "FAIL");
            $fclose(fd);
        end
    endtask

    // Robust AMBA Polling
    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; 
        do begin @(negedge pclk); end while(pready == 1'b0);
        psel=0; penable=0;
    endtask
    
    // Robust AMBA Polling
    task automatic apb_read(input [31:0] addr, output logic [31:0] data);
        @(negedge pclk); psel=1; pwrite=0; paddr=addr; pstrb=4'b0000;
        @(negedge pclk); penable=1; 
        do begin @(negedge pclk); end while(pready == 1'b0);
        data = prdata;
        psel=0; penable=0;
    endtask

    // Mock Flash: Instant drive on CS_n, wait for edge on subsequent nibbles
    initial begin
        reg [31:0] payload = 32'hDDF0_DDF0;
        forever begin
            @(negedge CS_n);
            slave_oe = 1;
            for (int i=7; i>=0; i--) begin 
                slave_drv = (payload >> (i*4)) & 4'hF; 
                if (i > 0) @(negedge CLK);
            end
            @(posedge CS_n); 
            slave_oe = 0; slave_drv = 4'hz;
        end
    end

    initial begin
        logic [31:0] val; 
        int timeout_ctr = 0;
        
        $dumpfile("dump_test_09.vcd"); $dumpvars(0, tb_test_09);
        $display("\n=======================================================================");
        $display(" TEST 09: DDR Protocol Parameters Synchronization");
        $display("=======================================================================\n");

        presetn = 0; #33; presetn = 1; @(posedge pclk);

        apb_write(32'h0C, 32'h0000_0000); // Max Speed
        apb_write(32'h00, 32'h0000_0401); // Quad Enable + Start RX
        
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 1000) begin
            @(posedge pclk); timeout_ctr++;
        end
        apb_read(32'h08, val);

        if (val === 32'hDDF0_DDF0) begin
            $display("   [PASS] DDR Protocol parameters synchronized. Payload: %h", val);
            update_summary("tb_test_09", 1);
        end else begin
            $display("   [FAIL] Data corruption. Got: %h", val);
            update_summary("tb_test_09", 0);
        end
        
        #100 $finish;
    end
endmodule
