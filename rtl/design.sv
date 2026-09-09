//=============================================================================
// Module: qspi_apb_master
// Purpose: APB3 slave + SPI/QSPI master controller with 8-deep TX/RX FIFOs.
//
// REVISION 2026-09-08 - RTL bug fixes (see notes at each site):
//   [FIX-1 to FIX-11] Retained from previous fixes.
//   [FIX-12] Added 'if (!busy)' protection to ctrl_reg[0] APB write logic to 
//            prevent software from overwriting the FSM's auto-clear behavior
//            during an active transaction, avoiding spurious restarts.
//=============================================================================
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

    localparam [7:0] ADDR_CTRL    = 8'h00;
    localparam [7:0] ADDR_TXDATA  = 8'h04;
    localparam [7:0] ADDR_RXDATA  = 8'h08;
    localparam [7:0] ADDR_CLKDIV  = 8'h0C;
    localparam [7:0] ADDR_XFERLEN = 8'h10;
    localparam [7:0] ADDR_DUMMY   = 8'h14;
    localparam [7:0] ADDR_STATUS  = 8'h18;
    localparam [7:0] ADDR_TIMEOUT = 8'h24;
    localparam [7:0] ADDR_DMA     = 8'h28;

    reg [31:0] ctrl_reg;
    reg [31:0] clkdiv_reg;
    reg [31:0] xferlen_reg;
    reg [31:0] dummy_ctrl;
    reg [31:0] timeout_ctrl;
    reg [31:0] dma_ctrl;

    localparam FIFO_DEPTH = 8;
    reg [31:0] tx_fifo [0:FIFO_DEPTH-1];
    reg [31:0] rx_fifo [0:FIFO_DEPTH-1];
    reg [2:0] tx_wr_ptr, tx_rd_ptr;
    reg [2:0] rx_wr_ptr, rx_rd_ptr;
    reg [3:0] tx_fifo_cnt, rx_fifo_cnt;

    wire tx_fifo_full  = (tx_fifo_cnt == 4'd8);
    wire tx_fifo_empty = (tx_fifo_cnt == 4'd0);
    wire rx_fifo_full  = (rx_fifo_cnt == 4'd8);
    wire rx_fifo_empty = (rx_fifo_cnt == 4'd0);

    localparam [2:0]
        ST_IDLE     = 3'd0,
        ST_CS_SETUP = 3'd1,
        ST_TX       = 3'd2,
        ST_DUMMY    = 3'd3,
        ST_RX       = 3'd4,
        ST_CS_HOLD  = 3'd5,
        ST_STOP     = 3'd6;

    reg [2:0]  state;
    reg [31:0] shift_reg;
    reg [5:0]  cycle_cnt;
    reg [7:0]  dummy_cnt;
    reg [31:0] timer_cnt;
    reg        oe;

    reg        spi_cpol;
    reg        spi_cpha;
    reg        spi_quad;
    reg [1:0]  spi_mode;
    reg [5:0]  spi_xfer_len;

    reg [15:0] clk_div_cnt;
    reg        spi_tick;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            clk_div_cnt <= 16'd0;
            spi_tick    <= 1'b0;
        end else begin
            if (state == ST_IDLE || state == ST_STOP || state == ST_CS_SETUP || state == ST_CS_HOLD) begin
                clk_div_cnt <= 16'd0;
                spi_tick    <= 1'b0;
            end else begin
                if (clk_div_cnt >= clkdiv_reg[15:0]) begin
                    clk_div_cnt <= 16'd0;
                    spi_tick    <= 1'b1;
                end else begin
                    clk_div_cnt <= clk_div_cnt + 1'b1;
                    spi_tick    <= 1'b0;
                end
            end
        end
    end

    wire d3_in = D3;
    wire d2_in = D2;
    wire d1_in = D1;
    wire d0_in = D0;

    wire apb_access   = psel && penable;
    wire apb_write_en = apb_access && pwrite && !pslverr;
    wire apb_read_en  = apb_access && !pwrite && !pslverr;
    wire addr_in_page = (paddr[31:8] == 24'd0);

    wire apb_ctrl_wr = apb_write_en && addr_in_page && (paddr[7:0] == ADDR_CTRL);
    wire apb_tx_wr   = apb_write_en && addr_in_page && (paddr[7:0] == ADDR_TXDATA);
    wire apb_rx_rd   = apb_read_en  && addr_in_page && (paddr[7:0] == ADDR_RXDATA);

    wire software_reset = apb_ctrl_wr && pstrb[1] && pwdata[8];
    wire busy = (state != ST_IDLE);

    wire valid_offset =
        (paddr[7:0] == ADDR_CTRL)    || (paddr[7:0] == ADDR_TXDATA)  ||
        (paddr[7:0] == ADDR_RXDATA)  || (paddr[7:0] == ADDR_CLKDIV)  ||
        (paddr[7:0] == ADDR_XFERLEN) || (paddr[7:0] == ADDR_DUMMY)   ||
        (paddr[7:0] == ADDR_STATUS)  || (paddr[7:0] == ADDR_TIMEOUT) ||
        (paddr[7:0] == ADDR_DMA);

    wire valid_address = addr_in_page && valid_offset;

    always @(*) begin
        pslverr = 1'b0;
        if (apb_access) begin
            if (!valid_address)
                pslverr = 1'b1;
            else if (paddr[1:0] != 2'b00)
                pslverr = 1'b1;
        end
    end

    always @(*) begin
        prdata = 32'h0000_0000;
        if (psel && penable && !pwrite && !pslverr) begin
            case (paddr[7:0])
                ADDR_CTRL:    prdata = {17'd0, ctrl_reg[14:0]};
                ADDR_TXDATA:  prdata = 32'h0;
                ADDR_RXDATA:  prdata = rx_fifo_empty ? 32'h0 : rx_fifo[rx_rd_ptr];
                ADDR_CLKDIV:  prdata = clkdiv_reg;
                ADDR_XFERLEN: prdata = xferlen_reg;
                ADDR_DUMMY:   prdata = dummy_ctrl;
                ADDR_STATUS:  prdata = {11'd0, busy, 12'd0, rx_fifo_cnt, tx_fifo_cnt};
                ADDR_TIMEOUT: prdata = timeout_ctrl;
                ADDR_DMA:     prdata = dma_ctrl;
                default:      prdata = 32'h0000_0000;
            endcase
        end
    end

    assign pready      = 1'b1;
    assign FLASH_RST_n = presetn && ctrl_reg[2];
    assign irq = ctrl_reg[3] && (ctrl_reg[4] || ctrl_reg[5] || ctrl_reg[7] || ctrl_reg[12]);

    assign tx_dma_req = dma_ctrl[0] && !tx_dma_ack && !tx_fifo_full &&
                        (tx_fifo_cnt <= dma_ctrl[11:8]);
    assign rx_dma_req = dma_ctrl[1] && !rx_dma_ack && !rx_fifo_empty &&
                        (rx_fifo_cnt >= dma_ctrl[19:16]);

    assign D3 = (oe && spi_quad) ? shift_reg[31] : 1'bz;
    assign D2 = (oe && spi_quad) ? shift_reg[30] : 1'bz;
    assign D1 = (oe && spi_quad) ? shift_reg[29] : 1'bz;
    assign D0 = oe ? (spi_quad ? shift_reg[28] : shift_reg[31]) : 1'bz;

    wire next_is_first_edge  = (CLK == spi_cpol);
    wire next_is_second_edge = (CLK != spi_cpol);
    wire sample_edge = spi_cpha ? next_is_second_edge : next_is_first_edge;
    wire shift_edge  = spi_cpha ? next_is_first_edge  : next_is_second_edge;
    wire last_cycle = (cycle_cnt == spi_xfer_len);

    wire [5:0] xfer_len_req = xferlen_reg[5:0];
    wire [5:0] xfer_len_max = ctrl_reg[10] ? 6'd7 : 6'd31;
    wire [5:0] xfer_len_clamped =
        (xfer_len_req > xfer_len_max) ? xfer_len_max : xfer_len_req;

    wire tx_apb_push = apb_tx_wr && !tx_fifo_full && !software_reset;
    wire rx_apb_pop  = apb_rx_rd && !rx_fifo_empty && !software_reset;

    reg tx_fsm_pop;
    reg rx_fsm_push;
    reg [3:0] cs_timer;

    wire int_sts_set = (state == ST_STOP);
    wire int_sts_clr = apb_ctrl_wr && pstrb[0] && pwdata[4];

    wire rx_ovr_set  = rx_fsm_push && rx_fifo_full;
    wire rx_ovr_clr  = apb_ctrl_wr && pstrb[0] && pwdata[7];

    wire tx_ovr_set  = apb_tx_wr && tx_fifo_full;
    wire tx_ovr_clr  = apb_ctrl_wr && pstrb[0] && pwdata[5];

    wire timeout_set = (timeout_ctrl != 0) && (timer_cnt >= timeout_ctrl) && busy;
    wire timeout_clr = apb_ctrl_wr && pstrb[1] && pwdata[12];

    integer i;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ctrl_reg     <= 32'h0000_0004;
            clkdiv_reg   <= 32'h0000_0001;
            xferlen_reg  <= 32'h0000_001F;
            dummy_ctrl   <= 32'h0;
            timeout_ctrl <= 32'h0;
            dma_ctrl     <= 32'h0;

            tx_wr_ptr    <= 3'd0;
            tx_rd_ptr    <= 3'd0;
            rx_wr_ptr    <= 3'd0;
            rx_rd_ptr    <= 3'd0;
            tx_fifo_cnt  <= 4'd0;
            rx_fifo_cnt  <= 4'd0;

            state        <= ST_IDLE;
            CS_n         <= 1'b1;
            CLK          <= 1'b0;
            oe           <= 1'b0;

            spi_cpol     <= 1'b0;
            spi_cpha     <= 1'b0;
            spi_quad     <= 1'b0;
            spi_mode     <= 2'b00;
            spi_xfer_len <= 6'd31;

            shift_reg    <= 32'd0;
            cycle_cnt    <= 6'd0;
            dummy_cnt    <= 8'd0;
            timer_cnt    <= 32'd0;

            tx_fsm_pop   <= 1'b0;
            rx_fsm_push  <= 1'b0;
            cs_timer     <= 4'd0;

            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                tx_fifo[i] <= 32'd0;
                rx_fifo[i] <= 32'd0;
            end
        end
        else begin
            tx_fsm_pop  <= 1'b0;
            rx_fsm_push <= 1'b0;

            if (busy)
                ctrl_reg[0] <= 1'b0;

            if (int_sts_set)      ctrl_reg[4] <= 1'b1;
            else if (int_sts_clr) ctrl_reg[4] <= 1'b0;

            if (tx_ovr_set)       ctrl_reg[5] <= 1'b1;
            else if (tx_ovr_clr)  ctrl_reg[5] <= 1'b0;

            if (rx_ovr_set)       ctrl_reg[7] <= 1'b1;
            else if (rx_ovr_clr)  ctrl_reg[7] <= 1'b0;

            if (timeout_set)      ctrl_reg[12] <= 1'b1;
            else if (timeout_clr) ctrl_reg[12] <= 1'b0;

            if (apb_ctrl_wr) begin
                if (pstrb[0]) begin
                    // [FIX-12] Protect manual start bit injection
                    if (!busy) ctrl_reg[0] <= pwdata[0];
                    ctrl_reg[1] <= pwdata[1];
                    ctrl_reg[2] <= pwdata[2];
                    ctrl_reg[3] <= pwdata[3];
                end
                if (pstrb[1]) begin
                    if (!busy) begin
                        ctrl_reg[9]  <= pwdata[9];
                        ctrl_reg[10] <= pwdata[10];
                        ctrl_reg[11] <= pwdata[11];
                    end
                    ctrl_reg[14:13] <= pwdata[14:13];
                end
            end

            if (apb_write_en && addr_in_page && paddr[7:0] == ADDR_CLKDIV) begin
                if (pstrb[0]) clkdiv_reg[7:0]   <= pwdata[7:0];
                if (pstrb[1]) clkdiv_reg[15:8]  <= pwdata[15:8];
                if (pstrb[2]) clkdiv_reg[23:16] <= pwdata[23:16];
                if (pstrb[3]) clkdiv_reg[31:24] <= pwdata[31:24];
            end

            if (apb_write_en && addr_in_page && paddr[7:0] == ADDR_XFERLEN) begin
                if (pstrb[0]) xferlen_reg[7:0]   <= pwdata[7:0];
                if (pstrb[1]) xferlen_reg[15:8]  <= pwdata[15:8];
                if (pstrb[2]) xferlen_reg[23:16] <= pwdata[23:16];
                if (pstrb[3]) xferlen_reg[31:24] <= pwdata[31:24];
            end

            if (apb_write_en && addr_in_page && paddr[7:0] == ADDR_DUMMY) begin
                if (pstrb[0]) dummy_ctrl[7:0] <= pwdata[7:0];
            end

            if (apb_write_en && addr_in_page && paddr[7:0] == ADDR_TIMEOUT) begin
                if (pstrb[0]) timeout_ctrl[7:0]   <= pwdata[7:0];
                if (pstrb[1]) timeout_ctrl[15:8]  <= pwdata[15:8];
                if (pstrb[2]) timeout_ctrl[23:16] <= pwdata[23:16];
                if (pstrb[3]) timeout_ctrl[31:24] <= pwdata[31:24];
            end

            if (apb_write_en && addr_in_page && paddr[7:0] == ADDR_DMA) begin
                if (pstrb[0]) dma_ctrl[7:0]   <= pwdata[7:0];
                if (pstrb[1]) dma_ctrl[15:8]  <= pwdata[15:8];
                if (pstrb[2]) dma_ctrl[23:16] <= pwdata[23:16];
                if (pstrb[3]) dma_ctrl[31:24] <= pwdata[31:24];
            end

            if (software_reset) begin
                state        <= ST_IDLE;
                CS_n         <= 1'b1;
                CLK          <= ctrl_reg[9];
                oe           <= 1'b0;
                shift_reg    <= 32'd0;
                cycle_cnt    <= 6'd0;
                dummy_cnt    <= 8'd0;
                timer_cnt    <= 32'd0;
                cs_timer     <= 4'd0;

                tx_wr_ptr    <= 3'd0;
                tx_rd_ptr    <= 3'd0;
                rx_wr_ptr    <= 3'd0;
                rx_rd_ptr    <= 3'd0;
                tx_fifo_cnt  <= 4'd0;
                rx_fifo_cnt  <= 4'd0;

                ctrl_reg[0]  <= 1'b0;
                ctrl_reg[4]  <= 1'b0;
                ctrl_reg[5]  <= 1'b0;
                ctrl_reg[7]  <= 1'b0;
                ctrl_reg[12] <= 1'b0;
            end
            else begin
                if (tx_apb_push) begin
                    tx_fifo[tx_wr_ptr][7:0]   <= pstrb[0] ? pwdata[7:0]   : 8'h00;
                    tx_fifo[tx_wr_ptr][15:8]  <= pstrb[1] ? pwdata[15:8]  : 8'h00;
                    tx_fifo[tx_wr_ptr][23:16] <= pstrb[2] ? pwdata[23:16] : 8'h00;
                    tx_fifo[tx_wr_ptr][31:24] <= pstrb[3] ? pwdata[31:24] : 8'h00;
                    tx_wr_ptr <= tx_wr_ptr + 1'b1;
                end

                if (rx_apb_pop) begin
                    rx_rd_ptr <= rx_rd_ptr + 1'b1;
                end

                if (rx_fsm_push && !rx_fifo_full) begin
                    rx_fifo[rx_wr_ptr] <= shift_reg;
                    rx_wr_ptr <= rx_wr_ptr + 1'b1;
                end

                case ({tx_apb_push, tx_fsm_pop})
                    2'b10:   tx_fifo_cnt <= tx_fifo_cnt + 1'b1;
                    2'b01:   tx_fifo_cnt <= tx_fifo_cnt - 1'b1;
                    default: tx_fifo_cnt <= tx_fifo_cnt;
                endcase

                case ({(rx_fsm_push && !rx_fifo_full), rx_apb_pop})
                    2'b10:   rx_fifo_cnt <= rx_fifo_cnt + 1'b1;
                    2'b01:   rx_fifo_cnt <= rx_fifo_cnt - 1'b1;
                    default: rx_fifo_cnt <= rx_fifo_cnt;
                endcase

                if (state == ST_IDLE)
                    timer_cnt <= 32'd0;
                else if (timeout_ctrl != 0 && timer_cnt < timeout_ctrl)
                    timer_cnt <= timer_cnt + 1'b1;

                if (timeout_set) begin
                    state    <= ST_IDLE;
                    CS_n     <= 1'b1;
                    CLK      <= spi_cpol;
                    oe       <= 1'b0;
                    cs_timer <= 4'd0;
                end
                else begin
                    case (state)
                        ST_IDLE: begin
                            CLK      <= ctrl_reg[9];
                            CS_n     <= 1'b1;
                            oe       <= 1'b0;
                            cs_timer <= 4'd0;

                            if (ctrl_reg[0]) begin
                                spi_cpol     <= ctrl_reg[9];
                                spi_cpha     <= ctrl_reg[11];
                                spi_quad     <= ctrl_reg[10];
                                spi_mode     <= ctrl_reg[14:13];
                                spi_xfer_len <= xfer_len_clamped; 
                                dummy_cnt    <= dummy_ctrl[7:0];
                                cycle_cnt    <= 6'd0;

                                CS_n         <= 1'b0;
                                cs_timer     <= 4'd0;
                                state        <= ST_CS_SETUP;
                            end
                        end

                        ST_CS_SETUP: begin
                            if (cs_timer >= 4'd1) begin
                                cs_timer <= 4'd0;
                                case (spi_mode)
                                    2'b00: begin
                                        oe        <= 1'b0;
                                        shift_reg <= 32'd0; 
                                        state     <= (dummy_cnt != 0) ? ST_DUMMY : ST_RX;
                                    end
                                    2'b01, 2'b10, 2'b11: begin
                                        if (!tx_fifo_empty) begin
                                            shift_reg  <= tx_fifo[tx_rd_ptr];
                                            tx_rd_ptr  <= tx_rd_ptr + 1'b1;
                                            tx_fsm_pop <= 1'b1;
                                            oe         <= 1'b1;
                                            state      <= ST_TX;
                                        end else begin
                                            state <= ST_STOP;
                                        end
                                    end
                                    default: begin
                                        state <= ST_STOP;
                                    end
                                endcase
                            end
                            else cs_timer <= cs_timer + 1'b1;
                        end

                        ST_TX: begin
                            if (spi_tick) begin
                                CLK <= ~CLK;
                                if (shift_edge) begin
                                    if (last_cycle) begin
                                        case (spi_mode)
                                            2'b01: state <= ST_CS_HOLD;
                                            2'b10: begin
                                                cycle_cnt <= 6'd0;
                                                oe        <= 1'b0;
                                                shift_reg <= 32'd0;
                                                state     <= ST_RX;
                                            end
                                            2'b11: begin
                                                oe        <= 1'b0;
                                                shift_reg <= 32'd0;
                                                state     <= (dummy_cnt != 0) ? ST_DUMMY : ST_RX;
                                                if (dummy_cnt == 0) cycle_cnt <= 6'd0;
                                            end
                                            default: state <= ST_CS_HOLD;
                                        endcase
                                    end
                                    else begin
                                        shift_reg <= spi_quad ? {shift_reg[27:0], 4'b0000} : {shift_reg[30:0], 1'b0};
                                        cycle_cnt <= cycle_cnt + 1'b1;
                                    end
                                end
                            end
                        end

                        ST_DUMMY: begin
                            if (spi_tick) begin
                                CLK <= ~CLK;
                                oe  <= 1'b0;
                                if (shift_edge) begin
                                    if (dummy_cnt <= 8'd1) begin
                                        dummy_cnt <= 8'd0;
                                        cycle_cnt <= 6'd0;
                                        shift_reg <= 32'd0;
                                        state     <= ST_RX;
                                    end
                                    else dummy_cnt <= dummy_cnt - 1'b1;
                                end
                            end
                        end

                        ST_RX: begin
                            if (spi_tick) begin
                                CLK <= ~CLK;
                                oe  <= 1'b0;
                                if (sample_edge) begin
                                    shift_reg <= spi_quad ? {shift_reg[27:0], d3_in, d2_in, d1_in, d0_in} : {shift_reg[30:0], d1_in};
                                    if (last_cycle) begin
                                        rx_fsm_push <= 1'b1;
                                        state       <= ST_CS_HOLD;
                                    end
                                    else cycle_cnt <= cycle_cnt + 1'b1;
                                end
                            end
                        end

                        ST_CS_HOLD: begin
                            CLK <= spi_cpol;
                            oe  <= 1'b0;
                            if (cs_timer >= 4'd1) begin
                                cs_timer <= 4'd0;
                                state    <= ST_STOP;
                            end
                            else cs_timer <= cs_timer + 1'b1;
                        end

                        ST_STOP: begin
                            CLK   <= spi_cpol;
                            CS_n  <= 1'b1;
                            oe    <= 1'b0;
                            state <= ST_IDLE;
                        end

                        default: begin
                            state <= ST_IDLE;
                            CS_n  <= 1'b1;
                            CLK   <= ctrl_reg[9];
                            oe    <= 1'b0;
                        end
                    endcase
                end
            end
        end
    end

endmodule