`timescale 1ns/1ps

// =========================================================================
// TEST 41: System Interrupt Generation & Clearing
// =========================================================================
module tb_test_41;

    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
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

    initial begin
        int timeout_ctr = 0;
        bit test_pass = 1'b1;

        $dumpfile("dump_test_41.vcd"); $dumpvars(0, tb_test_41);
        $display("\n=======================================================================");
        $display(" TEST 41: System Interrupt Generation & Clearing (QSPI-APB-REG-41)");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Triggering transfer with Global Interrupts ENABLED...");
        apb_write(32'h04, 32'hA5A5_5A5A); 
        // Start=1, TX=1, IntEn=1 -> 0x0B
        apb_write(32'h00, 32'h0000_000B); 

        // Bounded loop looking for IRQ
        while(irq == 1'b0 && timeout_ctr < 1000) begin
            @(posedge pclk); timeout_ctr++;
        end

        if (irq === 1'b1) begin
            $display("   [PASS] System Interrupt Generated! 'irq' pin HIGH.");
        end else begin
            $display("   [FAIL] Hardware failed to generate interrupt upon completion.");
            test_pass = 1'b0;
        end

        $display("2. CPU Acknowledging: Writing '1' to Interrupt Status to clear...");
        // Keep IntEn (Bit 3), Write 1 to clear IntSts (Bit 4) -> 0x18
        apb_write(32'h00, 32'h0000_0018);

        #10; 
        
        if (irq === 1'b0) begin
            $display("   [PASS] System Interrupt Cleared! 'irq' pin safely LOW.\n");
        end else begin
            $display("   [FAIL] Interrupt line stuck HIGH after W1C operation.\n");
            test_pass = 1'b0;
        end

        update_summary("tb_test_41", test_pass);
        #100 $finish;
    end
endmodule
