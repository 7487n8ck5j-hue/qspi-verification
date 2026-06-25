`timescale 1ns/1ps

module qspi_apb_master (
    input  wire        pclk,
    input  wire        presetn,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] paddr,
    input  wire [31:0] pwdata,
    input  wire [3:0]  pstrb,
    output reg  [31:0] prdata,
    output wire        pready,
    output reg         pslverr,     
    output wire        irq,

    // NEW: DMA Interface
    output wire        rx_dma_req,
    input  wire        rx_dma_ack,
    output wire        tx_dma_req,
    input  wire        tx_dma_ack,

    output reg         CS_n,
    output reg         CLK,
    output wire        FLASH_RST_n,
    inout  wire        D3,
    inout  wire        D2,
    inout  wire        D1,
    inout  wire        D0
);

    // CTRL_REG (0x00): 
    // B0=Start, B1=Dir, B2=Rst_n, B3=IntEn, B4=IntSts, B5=TX_Full, B6=RX_Empty, 
    // B7=RX_Overrun, B8=Soft_Reset, B9=CPOL, B10=Quad_Mode, B11=CPHA, B12=Timeout_Err
    reg [31:0] ctrl_reg;  
    reg [31:0] tx_reg;    
    reg [31:0] rx_reg;    
    reg [31:0] dummy_ctrl;
    reg [31:0] timeout_ctrl; // 0x24
    
    // DMA_CTRL (0x28): Bit 0 = TX DMA Enable, Bit 1 = RX DMA Enable, Bits 15:8 = TX Watermark, Bits 23:16 = RX Watermark
    reg [31:0] dma_ctrl;

    reg [3:0]  tx_fifo_cnt;
    reg [3:0]  rx_fifo_cnt;
    reg [31:0] timer_cnt;

    localparam IDLE = 3'd0, TX = 3'd1, DUMMY = 3'd2, RX = 3'd3, STOP = 3'd4;
    reg [2:0]  state;
    reg [31:0] shift_reg;
    reg [3:0]  cycle_cnt;
    reg [7:0]  dummy_cnt;
    reg        oe;

    assign FLASH_RST_n = ctrl_reg[2]; 
    assign pready      = 1'b1; 
    assign irq         = (ctrl_reg[3] && ctrl_reg[4]) || ctrl_reg[7] || ctrl_reg[12]; 

    // DMA Request Logic based on thresholds
    assign tx_dma_req = dma_ctrl[0] && (tx_fifo_cnt <= dma_ctrl[15:8]);
    assign rx_dma_req = dma_ctrl[1] && (rx_fifo_cnt >= dma_ctrl[23:16]);

    wire quad_en = ctrl_reg[10];
    assign D3 = (oe && quad_en) ? shift_reg[31] : 1'bz;
    assign D2 = (oe && quad_en) ? shift_reg[30] : 1'bz;
    assign D1 = (oe && quad_en) ? shift_reg[29] : 1'bz;
    assign D0 = oe ? shift_reg[28] : 1'bz; 

    wire leading_edge  = (CLK != ctrl_reg[9]);
    wire trailing_edge = (CLK == ctrl_reg[9]);
    wire sample_edge   = ctrl_reg[11] ? trailing_edge : leading_edge;
    wire shift_edge    = ctrl_reg[11] ? leading_edge  : trailing_edge;

    always @(*) begin
        pslverr = 1'b0;
        if (psel && penable && (paddr[7:0] > 8'h28)) pslverr = 1'b1;
    end

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ctrl_reg <= 32'h0000_0044; 
            tx_reg <= 32'h0; rx_reg <= 32'h0; dummy_ctrl <= 32'h0; timeout_ctrl <= 32'h0; dma_ctrl <= 32'h0;
            prdata <= 32'h0; tx_fifo_cnt <= 4'd0; rx_fifo_cnt <= 4'd0; timer_cnt <= 32'd0;
            state <= IDLE; CS_n <= 1'b1; CLK <= 1'b0;
            oe <= 1'b0; cycle_cnt <= 4'd0; shift_reg <= 32'd0; dummy_cnt <= 8'd0;
        end else begin
            if (state != IDLE) ctrl_reg[0] <= 1'b0; 
            ctrl_reg[5] <= (tx_fifo_cnt >= 4'd8);
            ctrl_reg[6] <= (rx_fifo_cnt == 4'd0);
            
            // DMA Acknowledgement Logic (Simulates pop/push directly from DMA)
            if (tx_dma_ack && tx_fifo_cnt < 8) tx_fifo_cnt <= tx_fifo_cnt + 1; // DMA pushed data
            if (rx_dma_ack && rx_fifo_cnt > 0) rx_fifo_cnt <= rx_fifo_cnt - 1; // DMA popped data
            
            // APB Write
            if (psel && penable && pwrite && !pslverr) begin
                case (paddr[7:0])
                    8'h00: begin 
                        if (pstrb[0]) ctrl_reg[3:0] <= pwdata[3:0]; 
                        if (pstrb[1]) ctrl_reg[12:8] <= pwdata[12:8]; 
                        if (pwdata[4]) ctrl_reg[4] <= 1'b0; 
                        if (pwdata[7]) ctrl_reg[7] <= 1'b0; 
                        if (pwdata[12]) ctrl_reg[12] <= 1'b0; 
                        if (pwdata[8]) begin 
                            state <= IDLE; CS_n <= 1'b1; oe <= 1'b0; timer_cnt <= 0;
                            tx_fifo_cnt <= 0; rx_fifo_cnt <= 0; ctrl_reg[0] <= 1'b0;
                        end
                    end
                    8'h04: begin 
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
            
            // APB Read
            if (psel && !pwrite && !pslverr) begin
                case (paddr[7:0])
                    8'h00: prdata <= {19'd0, ctrl_reg[12:0]};
                    8'h04: prdata <= tx_reg;
                    8'h08: begin 
                        prdata <= rx_reg; 
                        if (!rx_dma_ack && rx_fifo_cnt > 0) rx_fifo_cnt <= rx_fifo_cnt - 1; 
                    end 
                    8'h14: prdata <= dummy_ctrl;
                    8'h24: prdata <= timeout_ctrl;
                    8'h28: prdata <= dma_ctrl;
                    default: prdata <= 32'h0;
                endcase
            end

            // Hardware Watchdog Timer
            if (state == IDLE) timer_cnt <= 32'd0;
            else if (timeout_ctrl > 0) timer_cnt <= timer_cnt + 1;

            if (timeout_ctrl > 0 && timer_cnt >= timeout_ctrl) begin
                state <= IDLE; CS_n <= 1'b1; oe <= 1'b0; 
                ctrl_reg[12] <= 1'b1; // Trigger Timeout Error!
            end else if (!(psel && penable && pwrite && paddr[7:0]==8'h00 && pwdata[8])) begin
                
                // QSPI FSM 
                case (state)
                    IDLE: begin
                        CLK <= ctrl_reg[9]; CS_n <= 1'b1; oe <= 1'b0;
                        if (ctrl_reg[0]) begin
                            CS_n <= 1'b0; cycle_cnt <= 4'd0; shift_reg <= tx_reg;
                            if (tx_fifo_cnt > 0) tx_fifo_cnt <= tx_fifo_cnt - 1; 
                            dummy_cnt <= dummy_ctrl[7:0];
                            state <= ctrl_reg[1] ? TX : (dummy_ctrl[7:0] > 0 ? DUMMY : RX);
                            oe <= ctrl_reg[1];
                        end
                    end
                    TX: begin
                        CLK <= ~CLK;
                        if (shift_edge) begin 
                            if (cycle_cnt == 4'd7) state <= STOP;
                            else begin 
                                shift_reg <= quad_en ? {shift_reg[27:0], 4'd0} : {shift_reg[30:0], 1'b0}; 
                                cycle_cnt <= cycle_cnt + 1'b1; 
                            end
                        end
                    end
                    DUMMY: begin
                        CLK <= ~CLK; oe <= 1'b0;
                        if (shift_edge) begin
                            if (dummy_cnt == 8'd1) begin state <= RX; cycle_cnt <= 4'd0; end
                            else dummy_cnt <= dummy_cnt - 1'b1;
                        end
                    end
                    RX: begin
                        CLK <= ~CLK;
                        if (sample_edge) begin 
                            shift_reg <= quad_en ? {shift_reg[27:0], D3, D2, D1, D0} : {shift_reg[30:0], D1};
                            if (cycle_cnt == 4'd7) state <= STOP;
                            else cycle_cnt <= cycle_cnt + 1'b1;
                        end
                    end
                    STOP: begin
                        CLK <= ctrl_reg[9]; CS_n <= 1'b1; oe <= 1'b0; rx_reg <= shift_reg; 
                        ctrl_reg[4] <= 1'b1; 
                        if (rx_fifo_cnt < 4'd8) rx_fifo_cnt <= rx_fifo_cnt + 1; 
                        state <= IDLE;
                    end
                endcase
            end
        end
    end
endmodule