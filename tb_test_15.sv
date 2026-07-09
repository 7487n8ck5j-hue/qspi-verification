`timescale 1ns/1ps

// =========================================================================
// TEST 15: Read Data Capturing via Internal Taps
// =========================================================================
module tb_test_15;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    pullup(D3); pullup(D2); pullup(D1); pullup(D0); 

    reg slave_D1 = 1'bz; reg slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;

    qspi_apb_master dut (.*);
    always #5 pclk = ~pclk;

    // Standardized Makefile Tracking
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

    // Mock Flash: Aligned to Immediate Shift Edge
    initial begin
        reg [31:0] payload = 32'hFEED_BACC;
        forever begin
            @(negedge CS_n);
            slave_oe = 1;
            for (int i=31; i>=0; i--) begin 
                slave_D1 = payload[i]; // Drive data instantly
                if (i > 0) @(negedge CLK); 
            end
            @(posedge CS_n); 
            slave_oe = 0; slave_D1 = 1'bz;
        end
    end

    initial begin
        logic [31:0] val; 
        int timeout_ctr = 0;
        
        $dumpfile("dump_test_15.vcd"); $dumpvars(0, tb_test_15);
        $display("\n=======================================================================");
        $display(" TEST 15: QSPI-PHY-SDR-15");
        $display(" Read Data Capturing via Internal Taps");
        $display(" Validate data sampling bypassing the PHY Module.");
        $display("=======================================================================\n");

        presetn = 0; #33; presetn = 1; @(posedge pclk);

        apb_write(32'h00, 32'h0000_0001); // Start RX
        
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 1000) begin
            @(posedge pclk); timeout_ctr++;
        end

        apb_read(32'h08, val);
        
        // RTL reads 8 bits per RX phase by default, so we expect the top 8 bits of FEED_BACC (0xFE)
        if (val === 32'h0000_00FE) begin
            $display("   [PASS] Internal tap data captured successfully: %h\n", val);
            update_summary("tb_test_15", 1);
        end else begin
            $display("   [FAIL] Expected 0000_00FE, Got: %h\n", val);
            update_summary("tb_test_15", 0);
        end
        
        #100 $finish;
    end
endmodule
