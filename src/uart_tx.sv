// UART transmitter: one start bit, LSB-first data, one stop bit, no parity.
module uart_tx #(
    parameter int BAUD_RATE = 115_200,
    parameter int CLK_FREQ = 100_000_000,
    parameter int DATA_WIDTH = 8,
    localparam int CLOCKS_PER_BIT = CLK_FREQ / BAUD_RATE,
    localparam int COUNT_WIDTH = CLOCKS_PER_BIT > 1 ? $clog2(CLOCKS_PER_BIT) : 1,
    localparam int BIT_WIDTH = $clog2(DATA_WIDTH + 2)
) (
    input logic clk,
    input logic rst,
    output logic slv_ready,
    input logic slv_valid,
    input logic [DATA_WIDTH-1:0] slv_data,
    output logic tx
);
  logic [DATA_WIDTH+1:0] frame_q;
  logic [COUNT_WIDTH-1:0] count_q;
  logic [BIT_WIDTH-1:0] bit_q;
  logic busy_q;
  initial assert (BAUD_RATE > 0 && CLOCKS_PER_BIT >= 4 && DATA_WIDTH > 0)
    else $fatal(1, "Unsupported UART clock, baud rate or data width");
  assign slv_ready = !rst && !busy_q;
  assign tx = busy_q ? frame_q[0] : 1'b1;

  always_ff @(posedge clk) begin
    if (rst) begin
      frame_q <= '1;
      count_q <= '0;
      bit_q <= '0;
      busy_q <= 1'b0;
    end else if (slv_valid && slv_ready) begin
      frame_q <= {1'b1, slv_data, 1'b0};
      count_q <= COUNT_WIDTH'(CLOCKS_PER_BIT - 1);
      bit_q <= '0;
      busy_q <= 1'b1;
    end else if (busy_q) begin
      if (count_q != 0) count_q <= count_q - 1'b1;
      else if (bit_q == BIT_WIDTH'(DATA_WIDTH + 1)) busy_q <= 1'b0;
      else begin
        count_q <= COUNT_WIDTH'(CLOCKS_PER_BIT - 1);
        bit_q <= bit_q + 1'b1;
        frame_q <= {1'b1, frame_q[DATA_WIDTH+1:1]};
      end
    end
  end
endmodule
