`timescale 1ns/1ps

// =========================================================================
// TEST 28: Hardware Interrupt Masking Configuration
// =========================================================================
module tb_test_28;

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
    // Pullups simulate physical board resistors, preventing data lines from
    // floating to an unknown 'x' state when the bus is idle.
    // =====================================================================
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    
    qspi_apb_master dut (.*);
    
    // Generate a 100MHz clock (Toggles every 5ns)
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // - update_summary: Safely writes the PASS/FAIL result to the log file.
    // - apb_write/read: Replicates a cycle-accurate AMBA APB protocol 
    //   using a do-while loop to robustly wait for pready assertion.
    // =====================================================================
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
    // Implements a non-blocking mock flash response. It automatically 
    // drives the D1 (MISO) line high when CS_n is asserted, ensuring 
    // the simulator does not hang in infinite loops while waiting for data.
    // =====================================================================
    // Non-blocking Mock Flash to prevent infinite loop simulator crashes
    reg slave_oe = 0;
    assign D1 = slave_oe ? 1'b1 : 1'bz;
    always @(negedge CS_n) slave_oe <= 1;
    always @(posedge CS_n) slave_oe <= 0;

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Validates hardware interrupt masking configuration. It initiates a 
    // transfer with the interrupt enable bit intentionally cleared. It uses 
    // a bounded timeout to wait for completion, then verifies that the 
    // physical IRQ pin remained low while the internal status register 
    // correctly logged the completion of the operation.
    // =====================================================================
    initial begin
        logic [31:0] val;
        int timeout_ctr = 0; 
        bit test_pass = 1'b1;
        
        $dumpfile("dump_test_28.vcd"); $dumpvars(0, tb_test_28);
        $display("\n=======================================================================");
        $display(" TEST 28: Hardware Interrupt Masking Configuration");
        $display("=======================================================================\n");
        
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        $display("1. Configuring transfer with physical IRQ masked...");
        apb_write(32'h14, 32'h0000_0004); // Configure transfer length
        apb_write(32'h00, 32'h0000_0001); // Start without interrupts (Bit 3 = 0)

        // Increased timeout boundary 
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 10000) begin
            @(posedge pclk);
            timeout_ctr++;
        end

        if (timeout_ctr >= 10000) begin
            $display("   [FAIL] Hardware locked up. Bounded timeout reached.");
            test_pass = 1'b0;
        end

        #10;

        $display("2. Validating physical pin state...");
        if (irq === 1'b1) begin
            $display("   [FAIL] Physical irq pin went high despite IntEn mask.");
            test_pass = 1'b0;
        end else begin
            $display("   [PASS] Physical IRQ pin remained low.");
        end

        $display("3. Validating internal completion register status...");
        apb_read(32'h00, val);
        if (val[4] === 1'b1) begin
            $display("   [PASS] Internal complete bit logged properly.\n");
        end else begin
            $display("   [FAIL] Status register did not set complete bit.\n");
            test_pass = 1'b0;
        end

        update_summary("tb_test_28", test_pass);
        #100 $finish;
    end
endmodule
