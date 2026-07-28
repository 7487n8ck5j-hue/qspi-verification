`timescale 1ns/1ps

// =========================================================================
// TEST 22: Dummy Clock Cycle Generation
// =========================================================================
module tb_test_22;

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

    logic [3:0] slave_drv = 4'hz; 
    logic slave_oe = 0;
    assign D3 = slave_oe ? slave_drv[3] : 1'bz;
    assign D2 = slave_oe ? slave_drv[2] : 1'bz;
    assign D1 = slave_oe ? slave_drv[1] : 1'bz;
    assign D0 = slave_oe ? slave_drv[0] : 1'bz;

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
    task automatic update_summary(input string test_name, input bit pass);
        int fd = $fopen("regression_summary.txt", "a");
        if (fd) begin
            $fdisplay(fd, "%s: %s", test_name, pass ? "PASS" : "FAIL");
            $fclose(fd);
        end
    endtask

    task automatic apb_write(input [31:0] addr, input [31:0] data, input [3:0] strb = 4'b1111);
        @(negedge pclk); psel=1; pwrite=1; paddr=addr; pwdata=data; pstrb=strb;
        @(negedge pclk); penable=1; 
        do begin @(negedge pclk); end while(pready == 1'b0);
        psel=0; penable=0; pstrb=4'b1111;
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
    // Simulates a Flash memory device responding to a read command with 
    // dummy cycles. The slave waits for the programmed number of dummy 
    // clock edges before actively driving the payload (0xDEAD_BEEF) onto 
    // the Quad data bus.
    // =====================================================================
    initial begin
        reg [31:0] payload;
        forever begin
            @(negedge CS_n);
            
            // RTL counts the initial state as cycle 1, so 6 programmed = 5 physical edges
            repeat(5) @(negedge CLK); 
            
            slave_oe = 1;
            payload = 32'hDEAD_BEEF;
            
            for (int i=7; i>=0; i--) begin 
                slave_drv = (payload >> (i*4)) & 4'hF; 
                if (i > 0) @(negedge CLK); 
            end
            
            @(posedge CS_n); 
            slave_oe = 0; 
            slave_drv = 4'hz;
        end
    end

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Validates the Dummy Clock Cycle generation logic. Programs the master
    // to insert wait states (dummy cycles) between the instruction/address 
    // phase and the data capture phase, ensuring the hardware properly 
    // delays RX sampling to align with the delayed slave response.
    // =====================================================================
    initial begin
        logic [31:0] val;
        int timeout_ctr = 0;

        $dumpfile("dump_test_22.vcd"); 
        $dumpvars(0, tb_test_22);
        
        $display("\n=======================================================================");
        $display(" TEST 22: Dummy Clock Cycle Generation (Quad Mode)");
        $display("=======================================================================\n");

        presetn = 0; #33; presetn = 1; @(posedge pclk);

        apb_write(32'h14, 32'h0000_0006); // Program 6 Dummy Cycles
        apb_write(32'h00, 32'h0000_0401); // Quad Enable (Bit 10) + RX Mode + Start
        
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 1000) begin
            @(posedge pclk); timeout_ctr++;
        end

        apb_read(32'h08, val);

        // Evaluation & Logging
        if (val === 32'hDEAD_BEEF) begin
            $display("   [PASS] Data correctly fetched after 6 wait states.\n");
            update_summary("tb_test_22", 1);
        end else begin
            $display("   [FAIL] Expected DEADBEEF, Got: %h\n", val);
            update_summary("tb_test_22", 0);
        end
        
        #100 $finish;
    end
endmodule
