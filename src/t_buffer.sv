// Serialize a word into UART fragments, least significant fragment first.
module t_buffer #(
    parameter int DATA_WIDTH = 32,
    parameter int UART_DATA_WIDTH = 8,
    localparam int CHUNKS = DATA_WIDTH / UART_DATA_WIDTH,
    localparam int COUNT_WIDTH = CHUNKS > 1 ? $clog2(CHUNKS) : 1
) (
    input logic clk,
    input logic rst,
    input logic enable,
    input logic [DATA_WIDTH-1:0] slv_data,
    input logic slv_valid,
    output logic slv_ready,
    input logic uart_slv_ready,
    output logic uart_slv_valid,
    output logic [UART_DATA_WIDTH-1:0] uart_slv_data
);
  logic [DATA_WIDTH-1:0] data_q;
  logic [COUNT_WIDTH-1:0] count_q;
  initial assert (DATA_WIDTH >= UART_DATA_WIDTH && DATA_WIDTH % UART_DATA_WIDTH == 0)
    else $fatal(1, "Word width must be a multiple of the UART fragment width");
  assign slv_ready = !rst && enable && !uart_slv_valid;
  assign uart_slv_data = data_q[UART_DATA_WIDTH-1:0];
  always_ff @(posedge clk) begin
    if (rst || !enable) begin
      data_q <= '0;
      count_q <= '0;
      uart_slv_valid <= 1'b0;
    end else if (slv_valid && slv_ready) begin
      data_q <= slv_data;
      count_q <= '0;
      uart_slv_valid <= 1'b1;
    end else if (uart_slv_valid && uart_slv_ready) begin
      if (count_q == COUNT_WIDTH'(CHUNKS - 1)) uart_slv_valid <= 1'b0;
      else begin
        count_q <= count_q + 1'b1;
        data_q <= data_q >> UART_DATA_WIDTH;
      end
    end
  end
endmodule
