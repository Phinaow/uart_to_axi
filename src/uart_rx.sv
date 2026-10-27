// UART receiver: independent serial sampling with a one-word output mailbox.
// A full mailbox never corrupts its previous word; a new frame raises overrun.
module uart_rx #(
    parameter int BAUD_RATE = 115_200,
    parameter int CLK_FREQ = 100_000_000,
    parameter int DATA_WIDTH = 8,
    localparam int CLOCKS_PER_BIT = CLK_FREQ / BAUD_RATE,
    localparam int COUNT_WIDTH = CLOCKS_PER_BIT > 1 ? $clog2(CLOCKS_PER_BIT) : 1,
    localparam int BIT_WIDTH = DATA_WIDTH > 1 ? $clog2(DATA_WIDTH) : 1
) (
    input logic clk,
    input logic rst,
    output logic [DATA_WIDTH-1:0] mst_data,
    output logic mst_valid,
    input logic mst_ready,
    input logic rx,
    output logic framing_error_o,
    output logic overrun_error_o
);
  typedef enum logic [1:0] {Idle, Start, Data, Stop} state_t;
  state_t state_q;
  (* ASYNC_REG = "TRUE" *) logic [1:0] rx_sync_q;
  logic [COUNT_WIDTH-1:0] count_q;
  logic [BIT_WIDTH-1:0] bit_q;
  logic [DATA_WIDTH-1:0] data_q;
  initial assert (BAUD_RATE > 0 && CLOCKS_PER_BIT >= 4 && DATA_WIDTH > 0)
    else $fatal(1, "Unsupported UART clock, baud rate or data width");

  always_ff @(posedge clk) begin
    if (rst) rx_sync_q <= '1;
    else rx_sync_q <= {rx_sync_q[0], rx};
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= Idle;
      count_q <= '0;
      bit_q <= '0;
      data_q <= '0;
      mst_data <= '0;
      mst_valid <= 1'b0;
      framing_error_o <= 1'b0;
      overrun_error_o <= 1'b0;
    end else begin
      framing_error_o <= 1'b0;
      overrun_error_o <= 1'b0;
      if (mst_valid && mst_ready) mst_valid <= 1'b0;
      case (state_q)
        Idle: if (!rx_sync_q[1]) begin
          count_q <= COUNT_WIDTH'(CLOCKS_PER_BIT / 2 - 1);
          state_q <= Start;
        end
        Start: if (count_q != 0) count_q <= count_q - 1'b1;
          else if (rx_sync_q[1]) state_q <= Idle;
          else begin
            count_q <= COUNT_WIDTH'(CLOCKS_PER_BIT - 1);
            bit_q <= '0;
            state_q <= Data;
          end
        Data: if (count_q != 0) count_q <= count_q - 1'b1;
          else begin
            data_q[bit_q] <= rx_sync_q[1];
            count_q <= COUNT_WIDTH'(CLOCKS_PER_BIT - 1);
            if (bit_q == BIT_WIDTH'(DATA_WIDTH - 1)) state_q <= Stop;
            else bit_q <= bit_q + 1'b1;
          end
        Stop: if (count_q != 0) count_q <= count_q - 1'b1;
          else begin
            if (!rx_sync_q[1]) framing_error_o <= 1'b1;
            else if (mst_valid && !mst_ready) overrun_error_o <= 1'b1;
            else begin
              mst_data <= data_q;
              mst_valid <= 1'b1;
            end
            state_q <= Idle;
          end
        default: state_q <= Idle;
      endcase
    end
  end
endmodule
