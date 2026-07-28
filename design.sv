`timescale 1ns/1ps

module qspi_apb_master (
    // --------------------------------------------------------
    // APB Bus Interface Signals
    // --------------------------------------------------------
    input  wire        pclk,       // System clock
    input  wire        presetn,    // Active-low asynchronous reset
    input  wire        psel,       // APB peripheral select
    input  wire        penable,    // APB enable (second cycle of transfer)
    input  wire        pwrite,     // APB write/read control (1 = Write, 0 = Read)
    input  wire [31:0] paddr,      // APB address bus
    input  wire [31:0] pwdata,     // APB write data bus
    input  wire [3:0]  pstrb,      // APB write strobe (byte masking)
    output reg  [31:0] prdata,     // APB read data bus
    output wire        pready,     // APB ready signal (hardcoded to 1 for zero-wait states)
    output reg         pslverr,    // APB slave error (invalid address access)
    output wire        irq,        // System interrupt request line

    // --------------------------------------------------------
    // DMA Interface Signals
    // --------------------------------------------------------
    output wire        rx_dma_req, // Request DMA to read from RX FIFO
    input  wire        rx_dma_ack, // DMA acknowledges RX read
    output wire        tx_dma_req, // Request DMA to write to TX FIFO
    input  wire        tx_dma_ack, // DMA acknowledges TX write

    // --------------------------------------------------------
    // Physical QSPI Pins
    // --------------------------------------------------------
    output reg         CS_n,       // Active-low Chip Select
    output reg         CLK,        // SPI Clock
    output wire        FLASH_RST_n,// Active-low Flash Hardware Reset
    inout  wire        D3,         // Data Line 3 (HOLD_n / IO3)
    inout  wire        D2,         // Data Line 2 (WP_n / IO2)
    inout  wire        D1,         // Data Line 1 (MISO / IO1)
    inout  wire        D0          // Data Line 0 (MOSI / IO0)
);

    // ========================================================
    // Internal Memory-Mapped Registers
    // ========================================================
    // CTRL_REG (0x00): 
    // B0=Start, B1=Dir (1=TX, 0=RX), B2=Rst_n, B3=IntEn, B4=IntSts, B5=TX_Full, B6=RX_Empty, 
    // B7=RX_Overrun, B8=Soft_Reset, B9=CPOL, B10=Quad_Mode, B11=CPHA, B12=Timeout_Err
    reg [31:0] ctrl_reg;  
    reg [31:0] tx_reg;       // 0x04: Transmit Data Register / FIFO entrance
    reg [31:0] rx_reg;       // 0x08: Receive Data Register / FIFO exit
    reg [31:0] dummy_ctrl;   // 0x14: Number of dummy clock cycles
    reg [31:0] timeout_ctrl; // 0x24: Watchdog timer threshold
    reg [31:0] dma_ctrl;     // 0x28: DMA thresholds and enable flags

    // ========================================================
    // State Tracking & Counters
    // ========================================================
    reg [3:0]  tx_fifo_cnt;  // Tracks number of words in TX FIFO (max 8)
    reg [3:0]  rx_fifo_cnt;  // Tracks number of words in RX FIFO (max 8)
    reg [31:0] timer_cnt;    // Watchdog counter

    // Boundary Logic Registers
    reg [31:0] addr_ptr; 
    wire page_boundary_hit = (addr_ptr[7:0] == 8'hFF);

    // Finite State Machine (FSM) States
    localparam IDLE = 3'd0, TX = 3'd1, DUMMY = 3'd2, RX = 3'd3, STOP = 3'd4;
    reg [2:0]  state;
    reg [31:0] shift_reg;    // Internal shift register for serializing/deserializing data
    reg [3:0]  cycle_cnt;    // Tracks the 8 phases (nibbles or bits) of a 32-bit transfer
    reg [7:0]  dummy_cnt;    // Counts down dummy cycles
    reg        oe;           // Output Enable for tri-state buffers

    // ========================================================
    // Combinational Logic & Assignments
    // ========================================================
    assign FLASH_RST_n = ctrl_reg[2]; 
    assign pready      = 1'b1; // Always ready, APB accesses execute in 1 cycle
    assign irq         = (ctrl_reg[3] && ctrl_reg[4]) || ctrl_reg[7] || ctrl_reg[12]; 

    // DMA Request Logic based on thresholds set in dma_ctrl
    assign tx_dma_req = dma_ctrl[0] && (tx_fifo_cnt <= dma_ctrl[15:8]);
    assign rx_dma_req = dma_ctrl[1] && (rx_fifo_cnt >= dma_ctrl[23:16]);

    // Tri-state buffer control for Quad and Standard SPI modes
    wire quad_en = ctrl_reg[10];
    assign D3 = (oe && quad_en) ? shift_reg[31] : 1'bz;
    assign D2 = (oe && quad_en) ? shift_reg[30] : 1'bz;
    assign D1 = (oe && quad_en) ? shift_reg[29] : 1'bz;
    assign D0 = oe ? shift_reg[28] : 1'bz; 

    // SPI Clock Polarity (CPOL) and Phase (CPHA) Edge Detection
    wire leading_edge  = (CLK != ctrl_reg[9]);
    wire trailing_edge = (CLK == ctrl_reg[9]);
    wire sample_edge   = ctrl_reg[11] ? trailing_edge : leading_edge;
    wire shift_edge    = ctrl_reg[11] ? leading_edge  : trailing_edge;

    // Address bounds checking (Throws APB Slave Error if address > 0x28)
    always @(*) begin
        pslverr = 1'b0;
        if (psel && penable && (paddr[7:0] > 8'h28)) pslverr = 1'b1;
    end

    // ========================================================
    // Sequential Logic (APB Interface, DMA, Watchdog, FSM)
    // ========================================================
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            // ----------------------------------------------------
            // RESET CONDITION
            // ----------------------------------------------------
            ctrl_reg <= 32'h0000_0044; // Default: Reset high, Intsts cleared
            tx_reg <= 32'h0; rx_reg <= 32'h0; dummy_ctrl <= 32'h0; timeout_ctrl <= 32'h0; dma_ctrl <= 32'h0;
            prdata <= 32'h0; tx_fifo_cnt <= 4'd0; rx_fifo_cnt <= 4'd0; timer_cnt <= 32'd0;
            state <= IDLE; CS_n <= 1'b1; CLK <= 1'b0;
            oe <= 1'b0; cycle_cnt <= 4'd0; shift_reg <= 32'd0; dummy_cnt <= 8'd0;
        end else begin
            // ----------------------------------------------------
            // STATUS UPDATES & DMA HANDSHAKING
            // ----------------------------------------------------
            if (state != IDLE) ctrl_reg[0] <= 1'b0; // Auto-clear Start bit
            ctrl_reg[5] <= (tx_fifo_cnt >= 4'd8);   // Update TX_Full flag
            ctrl_reg[6] <= (rx_fifo_cnt == 4'd0);   // Update RX_Empty flag
            
            // DMA Acknowledgement Logic
            if (tx_dma_ack && tx_fifo_cnt < 8) tx_fifo_cnt <= tx_fifo_cnt + 1;
            if (rx_dma_ack && rx_fifo_cnt > 0) rx_fifo_cnt <= rx_fifo_cnt - 1;
            
            // ----------------------------------------------------
            // APB WRITE DECODER
            // ----------------------------------------------------
            if (psel && penable && pwrite && !pslverr) begin
                case (paddr[7:0])
                    8'h00: begin // Control Register
                        if (pstrb[0]) ctrl_reg[3:0] <= pwdata[3:0]; 
                        if (pstrb[1]) ctrl_reg[12:8] <= pwdata[12:8]; 
                        // Write-1-to-Clear (W1C) logic for interrupt flags
                        if (pwdata[4]) ctrl_reg[4] <= 1'b0; 
                        if (pwdata[7]) ctrl_reg[7] <= 1'b0; 
                        if (pwdata[12]) ctrl_reg[12] <= 1'b0; 
                        
                        // Software Reset Execution
                        if (pwdata[8]) begin 
                            state <= IDLE; CS_n <= 1'b1; oe <= 1'b0; timer_cnt <= 0;
                            tx_fifo_cnt <= 0; rx_fifo_cnt <= 0; ctrl_reg[0] <= 1'b0;
                        end
                    end
                    8'h04: begin // TX Data Register (Pushes to FIFO)
                        if (!tx_dma_ack) begin // Prevent APB and DMA fighting
                            if (pstrb[0]) tx_reg[7:0]   <= pwdata[7:0];
                            if (pstrb[1]) tx_reg[15:8]  <= pwdata[15:8];
                            if (pstrb[2]) tx_reg[23:16] <= pwdata[23:16];
                            if (pstrb[3]) tx_reg[31:24] <= pwdata[31:24];
                            if (tx_fifo_cnt < 8) tx_fifo_cnt <= tx_fifo_cnt + 1; 
                        end
                    end
                    8'h14: if (pstrb[0]) dummy_ctrl[7:0] <= pwdata[7:0];
                    8'h24: timeout_ctrl <= pwdata;
                    8'h28: dma_ctrl <= pwdata;
                endcase
            end
            
            // ----------------------------------------------------
            // APB READ DECODER
            // ----------------------------------------------------
            if (psel && !pwrite && !pslverr) begin
                case (paddr[7:0])
                    8'h00: prdata <= {19'd0, ctrl_reg[12:0]};
                    8'h04: prdata <= tx_reg;
                    8'h08: begin // RX Data Register (Pops from FIFO)
                        prdata <= rx_reg; 
                        if (!rx_dma_ack && rx_fifo_cnt > 0) rx_fifo_cnt <= rx_fifo_cnt - 1; 
                    end 
                    8'h14: prdata <= dummy_ctrl;
                    8'h24: prdata <= timeout_ctrl;
                    8'h28: prdata <= dma_ctrl;
                    default: prdata <= 32'h0;
                endcase
            end

            // ----------------------------------------------------
            // HARDWARE WATCHDOG TIMER
            // ----------------------------------------------------
            if (state == IDLE) timer_cnt <= 32'd0;
            else if (timeout_ctrl > 0) timer_cnt <= timer_cnt + 1;

            if (timeout_ctrl > 0 && timer_cnt >= timeout_ctrl) begin
                // Watchdog Timeout triggers abort and error flag
                state <= IDLE; CS_n <= 1'b1; oe <= 1'b0; 
                ctrl_reg[12] <= 1'b1; 
            end else if (!(psel && penable && pwrite && paddr[7:0]==8'h00 && pwdata[8])) begin
                
                // ----------------------------------------------------
                // QSPI FINITE STATE MACHINE (FSM)
                // ----------------------------------------------------
                case (state)
                    IDLE: begin
                        CLK <= ctrl_reg[9]; CS_n <= 1'b1; oe <= 1'b0;
                        if (ctrl_reg[0]) begin // Start bit triggered
                            CS_n <= 1'b0; cycle_cnt <= 4'd0; shift_reg <= tx_reg;
                            if (tx_fifo_cnt > 0) tx_fifo_cnt <= tx_fifo_cnt - 1; 
                            dummy_cnt <= dummy_ctrl[7:0];
                            // Determine next state based on Direction bit and Dummy Count
                            state <= ctrl_reg[1] ? TX : (dummy_ctrl[7:0] > 0 ? DUMMY : RX);
                            oe <= ctrl_reg[1];
                        end
                    end
                    TX: begin
                        CLK <= ~CLK;
                        if (shift_edge) begin 
                            if (cycle_cnt == 4'd7) state <= STOP;
                            else begin 
                                // Shift left by 4 bits for Quad, 1 bit for Standard
                                shift_reg <= quad_en ? {shift_reg[27:0], 4'd0} : {shift_reg[30:0], 1'b0}; 
                                cycle_cnt <= cycle_cnt + 1'b1; 
                            end
                        end
                    end
                    DUMMY: begin
                        CLK <= ~CLK; oe <= 1'b0; // Float bus during dummy cycles
                        if (shift_edge) begin
                            if (dummy_cnt == 8'd1) begin state <= RX; cycle_cnt <= 4'd0; end
                            else dummy_cnt <= dummy_cnt - 1'b1;
                        end
                    end
                    RX: begin
                        CLK <= ~CLK;
                        if (sample_edge) begin 
                            // Sample 4 bits for Quad, 1 bit for Standard
                            shift_reg <= quad_en ? {shift_reg[27:0], D3, D2, D1, D0} : {shift_reg[30:0], D1};
                            if (cycle_cnt == 4'd7) state <= STOP;
                            else cycle_cnt <= cycle_cnt + 1'b1;
                        end
                    end
                    STOP: begin
                        CLK <= ctrl_reg[9]; CS_n <= 1'b1; oe <= 1'b0; rx_reg <= shift_reg; 
                        ctrl_reg[4] <= 1'b1; // Set Interrupt Status flag
                        if (rx_fifo_cnt < 4'd8) rx_fifo_cnt <= rx_fifo_cnt + 1; // Push to RX FIFO
                        state <= IDLE;
                    end
                endcase
            end
        end
    end
endmodule
