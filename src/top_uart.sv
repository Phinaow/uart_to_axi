// UART loopback demo: collect BURST_LEN words, then transmit the complete burst.
module top_uart #(
    parameter int CLK_FREQ = 100_000_000,
    parameter int UART_BAUD_RATE = 115_200,
    parameter int UART_DATA_WIDTH = 8,
    parameter int DATA_WIDTH = 128,
    parameter int BURST_LEN = 3,
    localparam int COUNT_WIDTH = $clog2(BURST_LEN + 1)
) (
    input logic clk,
    input logic sys_rst,
    input logic rx,
    output logic tx
);
  wire rst = !sys_rst;
  logic [DATA_WIDTH-1:0] received_word, transmit_word;
  logic received_valid, received_ready, transmit_valid, transmit_ready;
  logic [UART_DATA_WIDTH-1:0] received_byte, transmit_byte;
  logic received_byte_valid, received_byte_ready, transmit_byte_valid, transmit_byte_ready;
  logic full, empty, push, pop, sending_q;
  logic [COUNT_WIDTH-1:0] count_q;
  initial assert (BURST_LEN > 0) else $fatal(1, "Burst length must be positive");
  assign received_ready = !rst && !sending_q && !full;
  assign transmit_valid = !rst && sending_q && !empty;
  assign push = received_valid && received_ready;
  assign pop = transmit_valid && transmit_ready;

  always_ff @(posedge clk) begin
    if (rst) begin
      count_q <= '0;
      sending_q <= 1'b0;
    end else if (push) begin
      count_q <= count_q + 1'b1;
      if (count_q == COUNT_WIDTH'(BURST_LEN - 1)) sending_q <= 1'b1;
    end else if (pop) begin
      count_q <= count_q - 1'b1;
      if (count_q == 1) sending_q <= 1'b0;
    end
  end

  fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(BURST_LEN)) words (
    .clk(clk), .rst(rst), .wr_data(received_word), .wr_en(push), .full(full),
    .rd_data(transmit_word), .rd_en(pop), .empty(empty)
  );
  r_buffer #(.DATA_WIDTH(DATA_WIDTH), .UART_DATA_WIDTH(UART_DATA_WIDTH)) input_buffer (
    .clk(clk), .rst(rst), .enable(1'b1), .mst_data(received_word), .mst_valid(received_valid),
    .mst_ready(received_ready), .uart_mst_data(received_byte),
    .uart_mst_valid(received_byte_valid), .uart_mst_ready(received_byte_ready)
  );
  t_buffer #(.DATA_WIDTH(DATA_WIDTH), .UART_DATA_WIDTH(UART_DATA_WIDTH)) output_buffer (
    .clk(clk), .rst(rst), .enable(1'b1), .slv_data(transmit_word), .slv_valid(transmit_valid),
    .slv_ready(transmit_ready), .uart_slv_data(transmit_byte),
    .uart_slv_valid(transmit_byte_valid), .uart_slv_ready(transmit_byte_ready)
  );
  uart_rx #(.BAUD_RATE(UART_BAUD_RATE), .CLK_FREQ(CLK_FREQ), .DATA_WIDTH(UART_DATA_WIDTH)) receiver (
    .clk(clk), .rst(rst), .rx(rx), .mst_data(received_byte), .mst_valid(received_byte_valid),
    .mst_ready(received_byte_ready), .framing_error_o(), .overrun_error_o()
  );
  uart_tx #(.BAUD_RATE(UART_BAUD_RATE), .CLK_FREQ(CLK_FREQ), .DATA_WIDTH(UART_DATA_WIDTH)) transmitter (
    .clk(clk), .rst(rst), .tx(tx), .slv_data(transmit_byte),
    .slv_valid(transmit_byte_valid), .slv_ready(transmit_byte_ready)
  );
endmodule
