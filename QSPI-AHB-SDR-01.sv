`timescale 1ns/1ps

// =========================================================================
// TEST 01: Single SPI Boot Payload Validation
// =========================================================================
module tb_test_01;

    // =====================================================================
    // Signal Declarations
    // ---------------------------------------------------------------------
    // Here we define all the physical pins connecting to the QSPI Master.
    // 'logic' is used for inputs we want to drive from the testbench.
    // 'wire' is used for outputs coming out of the DUT (Design Under Test).
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
    // 'pullup' ensures the data lines don't float to 'x' when nobody is driving them.
    // The (.*) automatically connects all matching wire names to the DUT ports.
    // =====================================================================
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);
    
    qspi_apb_master dut (.*);
    
    // Generate a 100MHz clock (Toggles every 5ns)
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // These tasks handle the repetitive actions of the testbench:
    // - update_summary: Safely writes the PASS/FAIL result to the text file.
    // - apb_write/read: Replicates standard AMBA APB bus timing protocol.
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
        @(negedge pclk); penable=1; wait(pready);
        @(negedge pclk); psel=0; penable=0;
    endtask

    task automatic apb_read(input [31:0] addr, output logic [31:0] data);
        @(negedge pclk); psel=1; pwrite=0; paddr=addr; pstrb=4'b0000;
        @(negedge pclk); penable=1; wait(pready);
        data = prdata;
        @(negedge pclk); psel=0; penable=0;
    endtask

    // =====================================================================
    // Mock SPI Flash Memory (The Slave)
    // ---------------------------------------------------------------------
    // This block acts like a real external Flash memory chip. 
    // When the master pulls CS_n low, it shifts out the "Boot Payload" 
    // byte-by-byte on the D1 (MISO) pin.
    // =====================================================================
    reg slave_D1 = 1'bz; 
    reg slave_oe = 0;
    assign D1 = slave_oe ? slave_D1 : 1'bz;

    initial begin
        reg [31:0] payload;
        slave_oe = 0;
        forever begin
            // Wait for the master to start a transaction
            @(negedge CS_n);
            
            #1; // 1ns safe delay prevents delta-cycle race conditions
            slave_oe = 1;
            payload = 32'hB007_C0DE; // The fake boot code we will send to the master
            
            // Shift out exactly 8 bits (MSB first) synced to the Master's clock
            for (int i=7; i>=0; i--) begin 
                slave_D1 = payload[24+i]; // Shifting out the 'B0' byte
                @(negedge CLK); 
            end
            
            #1; // 1ns safe delay guarantees we don't miss the posedge of CS_n
            slave_oe = 0; 
            slave_D1 = 1'bz;
            
            // Wait for the master to finish the transaction
            @(posedge CS_n);
        end
    end

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // The actual test execution block. It resets the DUT, triggers the 
    // SPI read, waits for it to finish, and evaluates the final result.
    // =====================================================================
    initial begin
        logic [31:0] val; 
        int timeout_ctr = 0;
        
        $dumpfile("dump_test_01.vcd"); 
        $dumpvars(0, tb_test_01);
        
        $display("\n=======================================================================");
        $display(" TEST 01: Boot Payload Validation");
        $display("=======================================================================\n");

        // 1. Hardware Reset
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        // 2. Pre-load TX FIFO with Dummy data (needed to trigger the clock FSM)
        apb_write(32'h04, 32'h0000_0000); 
        
        // 3. Trigger Transaction (Bit 0 = Start=1, Bit 1 = Dir=0 [RX Mode])
        apb_write(32'h00, 32'h0000_0001); 
        
        // 4. Wait for the QSPI hardware FSM to return to the IDLE state (state 0)
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 1000) begin
            @(posedge pclk); 
            timeout_ctr++;
        end
        
        // 5. Read the fetched data from the RX FIFO (0x08)
        apb_read(32'h08, val);

        // 6. Verify and Report
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
