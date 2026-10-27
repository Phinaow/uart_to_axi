// Synchronous FIFO with a combinational read port. A request presented while
// full/empty is ignored, including simultaneous requests at those boundaries.
module fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 256,
    localparam int ADDR_WIDTH = DEPTH > 1 ? $clog2(DEPTH) : 1,
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1)
) (
    input logic clk,
    input logic rst,
    input logic [DATA_WIDTH-1:0] wr_data,
    input logic wr_en,
    output logic full,
    output logic [DATA_WIDTH-1:0] rd_data,
    input logic rd_en,
    output logic empty
);
  logic [DATA_WIDTH-1:0] memory [DEPTH];
  logic [ADDR_WIDTH-1:0] write_q, read_q;
  logic [COUNT_WIDTH-1:0] count_q;
  logic push, pop;
  initial assert (DEPTH > 0 && DATA_WIDTH > 0) else $fatal(1, "Invalid FIFO dimensions");
  assign full = count_q == COUNT_WIDTH'(DEPTH);
  assign empty = count_q == 0;
  assign push = wr_en && !full;
  assign pop = rd_en && !empty;
  assign rd_data = memory[read_q];

  always_ff @(posedge clk) begin
    if (rst) begin
      write_q <= '0;
      read_q <= '0;
      count_q <= '0;
    end else begin
      if (push) begin
        memory[write_q] <= wr_data;
        write_q <= write_q == ADDR_WIDTH'(DEPTH - 1) ? '0 : write_q + 1'b1;
      end
      if (pop) read_q <= read_q == ADDR_WIDTH'(DEPTH - 1) ? '0 : read_q + 1'b1;
      case ({push, pop})
        2'b10: count_q <= count_q + 1'b1;
        2'b01: count_q <= count_q - 1'b1;
        default: ;
      endcase
    end
  end
endmodule
