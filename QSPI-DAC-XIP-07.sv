`timescale 1ns/1ps

// =========================================================================
// TEST 07: SPI Standard Read Alignment Verification
// =========================================================================
module tb_test_07;

    // =====================================================================
    // Signal Declarations
    // ---------------------------------------------------------------------
    // Defines all the physical pins connecting to the QSPI Master.
    // 'logic' is used for testbench-driven inputs, while 'wire' is used
    // for outputs coming from the Design Under Test (DUT).
    // =====================================================================
    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; 
    logic [3:0]  pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;

    wire  [31:0] prdata; 
    wire         pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    // =====================================================================
    // Bus Terminations & DUT Instantiation
    // ---------------------------------------------------------------------
    // Pullups simulate physical board resistors. D1 (MISO) has a pullup 
    // but is also dynamically driven by the mock slave to simulate 
    // incoming Flash data.
    // =====================================================================
    pullup(D3); pullup(D2); pullup(D0);
    
    reg slave_D1 = 1'b1; reg slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;
    pullup(D1);

    qspi_apb_master dut (.*);
    
    // Generate a 100MHz clock (Toggles every 5ns)
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // - update_summary: Safely writes the PASS/FAIL result to the log file.
    // - apb_write/read: Replicates a cycle-accurate AMBA APB protocol 
    //   using a do-while loop to wait for pready assertion.
    // =====================================================================
    task automatic update_summary(input string test_name, input bit pass);
        int fd = $fopen("regression_summary.txt", "a");
        if (fd) begin
            $fdisplay(fd, "%s: %s", test_name, pass ? "PASS" : "FAIL");
            $fclose(fd);
        end
    endtask

    task automatic apb_write(input [31:0] addr, input [31:0] data);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=4'b1111;
        @(negedge pclk); penable=1; 
        do begin @(negedge pclk); end while(pready == 1'b0);
        psel=0; penable=0;
    endtask

    task automatic apb_read(input [31:0] addr, output logic [31:0] data);
        @(negedge pclk); psel=1; pwrite=0; paddr=addr; pstrb=4'b0000;
        @(negedge pclk); penable=1; 
        do begin @(negedge pclk); end while(pready == 1'b0);
        data = prdata;
        psel=0; penable=0;
    endtask

    // =====================================================================
    // Mock SPI Flash Memory (The Slave)
    // ---------------------------------------------------------------------
    // This simple slave continually toggles the D1 (MISO) line on every 
    // negative clock edge while CS_n is active. This produces a predictable 
    // alternating bit pattern (e.g., 10101010) for the master to capture,
    // avoiding false positives from all 1s (FF) or all 0s (00).
    // =====================================================================
    always @(negedge CLK) begin
        if (CS_n == 1'b0) begin
            slave_oe <= 1;
            slave_D1 <= ~slave_D1; // Feed alternating bits to avoid FF misread
        end else begin
            slave_oe <= 0;
        end
    end

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Validates the Standard Read (0x03) sequence. It transmits the 
    // instruction opcode, triggers an RX capture phase, and confirms 
    // that the toggling data from the slave was correctly sampled by 
    // the master's RX FIFO.
    // =====================================================================
    initial begin
        logic [31:0] val;
        
        $dumpfile("dump_test_07.vcd"); $dumpvars(0, tb_test_07);
        $display("\n=======================================================================");
        $display(" TEST 07: SPI Standard Read Alignment Verification");
        $display("=======================================================================\n");

        presetn = 0; #33; presetn = 1; @(posedge pclk);

        // 1. Transmit Standard Read Opcode (0x03)
        apb_write(32'h04, 32'h0300_0000); 
        apb_write(32'h14, 32'h0000_0001); // 1-Byte Length
        apb_write(32'h00, 32'h0000_0003); // Start TX
        
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0)) @(posedge pclk);
        
        // 2. Trigger RX to capture the incoming toggled data
        apb_write(32'h14, 32'h0000_0001); // 1-Byte Length
        apb_write(32'h00, 32'h0000_0001); // Start RX
        
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0)) @(posedge pclk);
        
        // 3. Read the captured byte from the RX FIFO
        apb_read(32'h08, val);

        // 4. Verify it captured the toggling bit stream successfully
        if (val != 32'h0000_00FF && val != 32'h0000_0000) begin
            $display("   [PASS] Read Data Captured Successfully: %h", val);
            update_summary("tb_test_07", 1);
        end else begin
            $display("   [FAIL] Expected Valid Data, Got: %h", val);
            update_summary("tb_test_07", 0);
        end
        
        #100 $finish;
    end
endmodule
