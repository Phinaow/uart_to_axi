// Assemble UART fragments into a word, least significant fragment first.
module r_buffer #(
    parameter int DATA_WIDTH = 32,
    parameter int UART_DATA_WIDTH = 8,
    localparam int CHUNKS = DATA_WIDTH / UART_DATA_WIDTH,
    localparam int COUNT_WIDTH = CHUNKS > 1 ? $clog2(CHUNKS) : 1
) (
    input logic clk,
    input logic rst,
    input logic enable,
    output logic [DATA_WIDTH-1:0] mst_data,
    output logic mst_valid,
    input logic mst_ready,
    input logic uart_mst_valid,
    output logic uart_mst_ready,
    input logic [UART_DATA_WIDTH-1:0] uart_mst_data
);
  logic [COUNT_WIDTH-1:0] count_q;
  initial assert (DATA_WIDTH >= UART_DATA_WIDTH && DATA_WIDTH % UART_DATA_WIDTH == 0)
    else $fatal(1, "Word width must be a multiple of the UART fragment width");
  assign uart_mst_ready = !rst && enable && !mst_valid;
  always_ff @(posedge clk) begin
    if (rst || !enable) begin
      count_q <= '0;
      mst_data <= '0;
      mst_valid <= 1'b0;
    end else begin
      if (mst_valid && mst_ready) mst_valid <= 1'b0;
      if (uart_mst_valid && uart_mst_ready) begin
        mst_data[int'(count_q)*UART_DATA_WIDTH +: UART_DATA_WIDTH] <= uart_mst_data;
        if (count_q == COUNT_WIDTH'(CHUNKS - 1)) begin
          count_q <= '0;
          mst_valid <= 1'b1;
        end else count_q <= count_q + 1'b1;
      end
    end
  end
endmodule
