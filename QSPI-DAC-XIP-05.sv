`timescale 1ns/1ps

// =========================================================================
// TEST 05: QSPI Quad-SPI eXecute-In-Place (XIP) Boot Instruction Fetch
// =========================================================================
module tb_test_05;

    // =====================================================================
    // Signal Declarations
    // ---------------------------------------------------------------------
    // Defines all physical pins connecting to the QSPI Master.
    // Includes standard AMBA APB bus signals, DMA handshakes, and the 
    // 4-bit wide Quad-SPI physical interface (D0-D3).
    // =====================================================================
    logic        pclk = 0, presetn = 0, psel = 0, penable = 0, pwrite = 0;
    logic [31:0] paddr = 0, pwdata = 0; logic [3:0] pstrb = 4'b1111;
    logic        rx_dma_ack = 0, tx_dma_ack = 0;
    wire  [31:0] prdata; wire pready, pslverr, irq, rx_dma_req, tx_dma_req;
    wire         CS_n, CLK, FLASH_RST_n, D3, D2, D1, D0;

    // =====================================================================
    // Bus Terminations & DUT Instantiation
    // ---------------------------------------------------------------------
    // Pullups prevent the 4-bit data bus from floating to 'x'.
    // In Quad-SPI mode, the slave drives all 4 data lines simultaneously
    // when 'slave_oe' is active.
    // =====================================================================
    pullup(D3); pullup(D2); pullup(D1); pullup(D0);

    reg [3:0] slave_drv = 4'b0000; logic slave_oe = 0;
    assign D3 = slave_oe ? slave_drv[3] : 1'bz;
    assign D2 = slave_oe ? slave_drv[2] : 1'bz;
    assign D1 = slave_oe ? slave_drv[1] : 1'bz;
    assign D0 = slave_oe ? slave_drv[0] : 1'bz;

    qspi_apb_master dut (.*);
    always #5 pclk = ~pclk;

    // =====================================================================
    // Reusable Verification Tasks
    // ---------------------------------------------------------------------
    // - update_summary: Safely appends the PASS/FAIL result to the log.
    // - apb_write/read: Replicates cycle-accurate AMBA APB bus protocol.
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
        @(negedge pclk); penable=1; wait(pready); data = prdata;
        @(negedge pclk); psel=0; penable=0;
    endtask

    // =====================================================================
    // Mock Quad-SPI Flash Memory (The Slave)
    // ---------------------------------------------------------------------
    // Simulates a high-speed QSPI Flash memory chip. 
    // Instead of shifting 1 bit per clock cycle, it shifts an entire 4-bit 
    // nibble per clock cycle, drastically speeding up the data transfer.
    // =====================================================================
    initial begin
        reg [31:0] payload = 32'h1A57_8C73;
        forever begin
            @(negedge CS_n);
            #1; slave_oe = 1;
            slave_drv = (payload >> (7*4)) & 4'hF; 
            for (int i=6; i>=0; i--) begin 
                @(negedge CLK); 
                #1; slave_drv = (payload >> (i*4)) & 4'hF; 
            end
            @(posedge CS_n); 
            #1; slave_oe = 0;
        end
    end

    // =====================================================================
    // Main Test Sequence
    // ---------------------------------------------------------------------
    // Verifies that the QSPI master can successfully enable Quad Mode, 
    // trigger a transaction, and correctly reassemble the 4-bit parallel 
    // streams back into a complete 32-bit word in the RX FIFO.
    // =====================================================================
    initial begin
        logic [31:0] val; int timeout_ctr = 0;
        $dumpfile("dump_test_05.vcd"); $dumpvars(0, tb_test_05);
        presetn = 0; #33; presetn = 1; @(posedge pclk);

        // 1. Configure and trigger the master:
        //    Bit 10 = Quad Enable (1), Bit 0 = Start (1) -> 0x0401
        apb_write(32'h00, 32'h0000_0401);
        
        // 2. Wait for the QSPI FSM to finish the high-speed transfer
        while ((dut.state != 3'd0 || dut.ctrl_reg[0] != 1'b0) && timeout_ctr < 1000) begin
            @(posedge pclk); timeout_ctr++;
        end
        
        // 3. Read the assembled 32-bit payload from the RX FIFO
        apb_read(32'h08, val);

        // 4. Verify the results
        if (timeout_ctr >= 1000) begin
            $display("   [FAIL] Hardware locked up during XIP fetch.");
            update_summary("tb_test_05", 0);
        end else if (val === 32'h1A57_8C73) begin
            $display("   [PASS] High-Speed Quad Boot Instruction Fetched: %h\n", val);
            update_summary("tb_test_05", 1);
        end else begin
            $display("   [FAIL] Expected 1A578C73, Got: %h\n", val);
            update_summary("tb_test_05", 0);
        end

        #100 $finish;
    end
endmodule
