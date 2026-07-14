`timescale 1ns/1ps

module pl_uart_ps_bridge #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200,
    parameter integer FIFO_DEPTH = 16
) (
    input  wire       clk,
    input  wire       rstn,
    input  wire       uart_rx,
    output logic      uart_tx,

    output wire [7:0] rx_data,
    output wire       rx_valid,
    input  wire       rx_pop,
    output wire [4:0] rx_count,

    input  wire [7:0] tx_data,
    input  wire       tx_push,
    output wire       tx_ready,
    output wire [4:0] tx_count,

    input  wire       clear_errors,
    output logic      rx_overrun,
    output logic      rx_framing_error
);
    localparam integer CLKS_PER_BIT = (CLK_HZ + (BAUD / 2)) / BAUD;
    localparam integer PTR_W = $clog2(FIFO_DEPTH);

    typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
    typedef enum logic [1:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP} tx_state_t;

    logic [7:0] rx_fifo [0:FIFO_DEPTH-1];
    logic [7:0] tx_fifo [0:FIFO_DEPTH-1];
    logic [PTR_W-1:0] rx_wr_ptr, rx_rd_ptr, tx_wr_ptr, tx_rd_ptr;
    logic [PTR_W:0] rx_count_reg, tx_count_reg;

    logic uart_rx_meta, uart_rx_sync;
    rx_state_t rx_state;
    tx_state_t tx_state;
    logic [15:0] rx_clk_count, tx_clk_count;
    logic [2:0] rx_bit_index, tx_bit_index;
    logic [7:0] rx_shift, tx_shift;
    logic rx_byte_push;
    logic [7:0] rx_byte_data;
    logic tx_byte_pop;

    wire rx_fifo_full = (rx_count_reg == FIFO_DEPTH);
    wire tx_fifo_empty = (tx_count_reg == 0);
    wire rx_pop_accept = rx_pop && (rx_count_reg != 0);
    wire tx_push_accept = tx_push && (tx_count_reg != FIFO_DEPTH);
    wire rx_push_accept = rx_byte_push && !rx_fifo_full;

    assign rx_data = rx_fifo[rx_rd_ptr];
    assign rx_valid = (rx_count_reg != 0);
    assign rx_count = rx_count_reg[4:0];
    assign tx_ready = (tx_count_reg != FIFO_DEPTH);
    assign tx_count = tx_count_reg[4:0];

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            uart_rx_meta <= 1'b1;
            uart_rx_sync <= 1'b1;
        end else begin
            uart_rx_meta <= uart_rx;
            uart_rx_sync <= uart_rx_meta;
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rx_state <= RX_IDLE;
            rx_clk_count <= 16'd0;
            rx_bit_index <= 3'd0;
            rx_shift <= 8'd0;
            rx_byte_push <= 1'b0;
            rx_byte_data <= 8'd0;
            rx_framing_error <= 1'b0;
        end else begin
            rx_byte_push <= 1'b0;
            if (clear_errors) rx_framing_error <= 1'b0;
            case (rx_state)
                RX_IDLE: begin
                    if (!uart_rx_sync) begin
                        rx_clk_count <= (CLKS_PER_BIT / 2) - 1;
                        rx_state <= RX_START;
                    end
                end
                RX_START: begin
                    if (rx_clk_count != 0) rx_clk_count <= rx_clk_count - 1'b1;
                    else if (!uart_rx_sync) begin
                        rx_clk_count <= CLKS_PER_BIT - 1;
                        rx_bit_index <= 3'd0;
                        rx_state <= RX_DATA;
                    end else rx_state <= RX_IDLE;
                end
                RX_DATA: begin
                    if (rx_clk_count != 0) rx_clk_count <= rx_clk_count - 1'b1;
                    else begin
                        rx_shift[rx_bit_index] <= uart_rx_sync;
                        rx_clk_count <= CLKS_PER_BIT - 1;
                        if (rx_bit_index == 3'd7) rx_state <= RX_STOP;
                        else rx_bit_index <= rx_bit_index + 1'b1;
                    end
                end
                RX_STOP: begin
                    if (rx_clk_count != 0) rx_clk_count <= rx_clk_count - 1'b1;
                    else begin
                        if (uart_rx_sync) begin
                            rx_byte_data <= rx_shift;
                            rx_byte_push <= 1'b1;
                        end else rx_framing_error <= 1'b1;
                        rx_state <= RX_IDLE;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rx_wr_ptr <= '0;
            rx_rd_ptr <= '0;
            rx_count_reg <= '0;
            rx_overrun <= 1'b0;
        end else begin
            if (clear_errors) rx_overrun <= 1'b0;
            if (rx_byte_push && rx_fifo_full) rx_overrun <= 1'b1;
            if (rx_push_accept) begin
                rx_fifo[rx_wr_ptr] <= rx_byte_data;
                rx_wr_ptr <= rx_wr_ptr + 1'b1;
            end
            if (rx_pop_accept) rx_rd_ptr <= rx_rd_ptr + 1'b1;
            case ({rx_push_accept, rx_pop_accept})
                2'b10: rx_count_reg <= rx_count_reg + 1'b1;
                2'b01: rx_count_reg <= rx_count_reg - 1'b1;
                default: rx_count_reg <= rx_count_reg;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tx_wr_ptr <= '0;
            tx_rd_ptr <= '0;
            tx_count_reg <= '0;
        end else begin
            if (tx_push_accept) begin
                tx_fifo[tx_wr_ptr] <= tx_data;
                tx_wr_ptr <= tx_wr_ptr + 1'b1;
            end
            if (tx_byte_pop) tx_rd_ptr <= tx_rd_ptr + 1'b1;
            case ({tx_push_accept, tx_byte_pop})
                2'b10: tx_count_reg <= tx_count_reg + 1'b1;
                2'b01: tx_count_reg <= tx_count_reg - 1'b1;
                default: tx_count_reg <= tx_count_reg;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tx_state <= TX_IDLE;
            tx_clk_count <= 16'd0;
            tx_bit_index <= 3'd0;
            tx_shift <= 8'd0;
            tx_byte_pop <= 1'b0;
            uart_tx <= 1'b1;
        end else begin
            tx_byte_pop <= 1'b0;
            case (tx_state)
                TX_IDLE: begin
                    uart_tx <= 1'b1;
                    if (!tx_fifo_empty) begin
                        tx_shift <= tx_fifo[tx_rd_ptr];
                        tx_byte_pop <= 1'b1;
                        tx_clk_count <= CLKS_PER_BIT - 1;
                        uart_tx <= 1'b0;
                        tx_state <= TX_START;
                    end
                end
                TX_START: begin
                    if (tx_clk_count != 0) tx_clk_count <= tx_clk_count - 1'b1;
                    else begin
                        uart_tx <= tx_shift[0];
                        tx_bit_index <= 3'd0;
                        tx_clk_count <= CLKS_PER_BIT - 1;
                        tx_state <= TX_DATA;
                    end
                end
                TX_DATA: begin
                    if (tx_clk_count != 0) tx_clk_count <= tx_clk_count - 1'b1;
                    else begin
                        tx_clk_count <= CLKS_PER_BIT - 1;
                        if (tx_bit_index == 3'd7) begin
                            uart_tx <= 1'b1;
                            tx_state <= TX_STOP;
                        end else begin
                            tx_bit_index <= tx_bit_index + 1'b1;
                            uart_tx <= tx_shift[tx_bit_index + 1'b1];
                        end
                    end
                end
                TX_STOP: begin
                    if (tx_clk_count != 0) tx_clk_count <= tx_clk_count - 1'b1;
                    else tx_state <= TX_IDLE;
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end
endmodule
