`timescale 1ns/1ps

// =========================================================================
// TEST 01: Single SPI Boot Payload Validation
// =========================================================================
module tb_test_01;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    
    reg slave_D1 = 1'bz; 
    reg slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;

    qspi_apb_master dut (.*);
    always #5 pclk = ~pclk;

    // FIX: Updated task to accept test name and status correctly
    task automatic update_summary(input string test_name, input bit pass);
        int fd = $fopen("regression_summary.txt", "a");
        if (fd) begin
            // FIX: Use %s for the test name and result string
            $fdisplay(fd, "%s: %s", test_name, pass ? "PASS" : "FAIL");
            $fclose(fd);
        end
    endtask

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

    initial begin
        reg [31:0] payload;
        slave_oe = 0;
        forever begin
            @(negedge CS_n);
            slave_oe = 1;
            payload = 32'hB007_C0DE;
            for (int i=7; i>=0; i--) begin 
                slave_D1 = payload[24+i];
                @(negedge CLK); 
            end
            slave_oe = 0; slave_D1 = 1'bz;
            @(posedge CS_n);
        end
    end

    initial begin
        logic [31:0] val; 
        int timeout_ctr = 0;
        
        $dumpfile("dump_test_01.vcd"); 
        $dumpvars(0, tb_test_01);
        
        $display("\n=======================================================================");
        $display(" TEST 01: Boot Payload Validation");
        $display("=======================================================================\n");

        presetn = 0; #33; presetn = 1; @(posedge pclk);

        apb_write(32'h04, 32'h0000_0000); 
        apb_write(32'h00, 32'h0000_0001); 
        
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 1000) begin
            @(posedge pclk); timeout_ctr++;
        end
        
        apb_read(32'h08, val);

        if (val === 32'h0000_00B0) begin
            $display("   [PASS] Boot Payload Validated: %h\n", val);
            update_summary("tb_test_01", 1); 
        end else begin
            $display("   [FAIL] Expected 0000_00B0, Got: %h\n", val);
            update_summary("tb_test_01", 0); 
        end

        #100 $finish;
    end
endmodule
