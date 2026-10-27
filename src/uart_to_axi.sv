// One-command-at-a-time UART protocol. Words and serial bytes are little endian.
// WRIT: address, data -> status. READ: address -> data, status.
// CMDA -> RESP. TEMP -> cycle counter. Unknown commands -> ???? .
module uart_to_axi #(
    parameter int BAUD_RATE = 115_200,
    parameter int CLK_FREQ = 100_000_000,
    parameter int UART_DATA_WIDTH = 8,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32
) (
    input logic clk,
    input logic rst,
    input logic rx,
    output logic tx,
    output logic [ADDR_WIDTH-1:0] axi_awaddr,
    output logic axi_awvalid,
    input logic axi_awready,
    output logic [DATA_WIDTH-1:0] axi_wdata,
    output logic axi_wvalid,
    input logic axi_wready,
    output logic [DATA_WIDTH/8-1:0] axi_wstrb,
    input logic [1:0] axi_bresp,
    input logic axi_bvalid,
    output logic axi_bready,
    output logic [ADDR_WIDTH-1:0] axi_araddr,
    output logic axi_arvalid,
    input logic axi_arready,
    input logic [DATA_WIDTH-1:0] axi_rdata,
    input logic [1:0] axi_rresp,
    input logic axi_rvalid,
    output logic axi_rready,
    input logic [31:0] cycle_ct,
    output logic rx_error_o
);
  localparam logic [31:0] WRIT = 32'h54495257, READ = 32'h44414552;
  localparam logic [31:0] OKAY = 32'h59414B4F, ErrorStatus = 32'h21525245;
  localparam logic [31:0] INFO = 32'h4F464E49, RDEX = 32'h58454452;
  localparam logic [31:0] WMSK = 32'h4B534D57, RBLK = 32'h4B4C4252;
  localparam logic [31:0] WBLK = 32'h4B4C4257;
  localparam logic [31:0] CAPABILITIES = 32'h0100FFFF;
  typedef enum logic [4:0] {
    Command, WriteAddress, WriteData, ReadAddress,
    StartWrite, WaitWrite, StartRead, WaitRead, SendData, SendStatus, Fault,
    BlockControl, BlockData, WriteMask, NextAccess
  } state_t;
  state_t state_q;
  typedef enum logic [2:0] {Legacy, ExtendedRead, MaskedWrite, BlockRead, BlockWrite} mode_t;
  mode_t mode_q;
  logic [3:0] write_mask_q;
  logic [8:0] block_count_q, block_index_q;
  logic fixed_address_q;
  logic [31:0] block_data_q [256];
  logic [32:0] unused_block_last_address;
  logic [3:0] full_write_strobes;
  logic [DATA_WIDTH-1:0] input_word, output_word_q, read_data;
  logic input_valid, input_ready, output_ready, output_valid;
  logic [UART_DATA_WIDTH-1:0] rx_data, tx_data;
  logic rx_valid, rx_ready, tx_valid, tx_ready;
  logic framing_error, overrun_error;
  logic [ADDR_WIDTH-1:0] write_address_q, read_address_q;
  logic [DATA_WIDTH-1:0] write_data_q;
  logic write_done, read_done;
  logic [1:0] write_status, read_status;
  logic read_failed_q;
  logic [1:0] read_status_q;
  logic rx_fault_q;

  assign axi_wstrb = write_mask_q & full_write_strobes;
  assign unused_block_last_address = {1'b0, write_address_q} +
                              (({17'b0, input_word[15:0]} - 33'd1) << 2);

  initial assert (DATA_WIDTH == 32 && ADDR_WIDTH == 32 && UART_DATA_WIDTH == 8)
    else $fatal(1, "The serial command protocol uses 32-bit words and 8-bit bytes");
  assign input_ready = !rst && !rx_fault_q && (state_q == Command || state_q == WriteAddress ||
                               state_q == WriteData || state_q == ReadAddress ||
                               state_q == BlockControl || state_q == BlockData ||
                               state_q == WriteMask);
  assign output_valid = !rst && (state_q == SendData || state_q == SendStatus);
  assign rx_error_o = rx_fault_q || framing_error || overrun_error;

  // The mask is part of the AXI write payload and must survive backpressure.
  assert property (@(posedge clk) disable iff (rst)
    axi_wvalid && !axi_wready |=> axi_wvalid && $stable(axi_wstrb));

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= Command;
      mode_q <= Legacy;
      write_mask_q <= 4'hF;
      block_count_q <= '0;
      block_index_q <= '0;
      fixed_address_q <= 1'b0;
      output_word_q <= '0;
      write_address_q <= '0;
      read_address_q <= '0;
      write_data_q <= '0;
      read_failed_q <= 1'b0;
      read_status_q <= '0;
      rx_fault_q <= 1'b0;
    end else if (!rx_fault_q && (framing_error || overrun_error)) begin
      // A lost byte destroys word alignment. Report once, then require reset
      // rather than interpreting a shifted byte stream as new memory commands.
      rx_fault_q <= 1'b1;
      output_word_q <= ErrorStatus;
      state_q <= SendStatus;
    end else begin
      case (state_q)
        Command: if (input_valid && input_ready) begin
          mode_q <= Legacy;
          write_mask_q <= 4'hF;
          block_index_q <= '0;
          case (input_word)
            INFO: begin output_word_q <= CAPABILITIES; state_q <= SendStatus; end
            RDEX: begin mode_q <= ExtendedRead; state_q <= ReadAddress; end
            WMSK: begin mode_q <= MaskedWrite; state_q <= WriteAddress; end
            RBLK: begin mode_q <= BlockRead; state_q <= WriteAddress; end
            WBLK: begin mode_q <= BlockWrite; state_q <= WriteAddress; end
            WRIT: state_q <= WriteAddress;
            READ: state_q <= ReadAddress;
            32'h41444D43: begin output_word_q <= 32'h50534552; state_q <= SendStatus; end
            32'h504D4554: begin output_word_q <= cycle_ct; state_q <= SendStatus; end
            default: begin output_word_q <= 32'h3F3F3F3F; state_q <= SendStatus; end
          endcase
        end
        WriteAddress: if (input_valid && input_ready) begin
          write_address_q <= input_word;
          state_q <= (mode_q == BlockRead || mode_q == BlockWrite) ? BlockControl : WriteData;
        end
        WriteData: if (input_valid && input_ready) begin
          write_data_q <= input_word;
          state_q <= mode_q == MaskedWrite ? WriteMask : StartWrite;
        end
        ReadAddress: if (input_valid && input_ready) begin
          read_address_q <= input_word;
          state_q <= StartRead;
        end
        WriteMask: if (input_valid && input_ready) begin
          if (input_word[31:4] != 0) begin
            output_word_q <= ErrorStatus;
            mode_q <= Legacy;
            state_q <= SendStatus;
          end else begin
            write_mask_q <= input_word[3:0];
            state_q <= StartWrite;
          end
        end
        BlockControl: if (input_valid && input_ready) begin
          if (input_word[31:17] != 0 || input_word[15:0] == 0 ||
              input_word[15:0] > 256 || (!input_word[16] && unused_block_last_address[32])) begin
            output_word_q <= ErrorStatus;
            mode_q <= Legacy;
            state_q <= SendStatus;
          end else begin
            block_count_q <= input_word[8:0];
            fixed_address_q <= input_word[16];
            read_address_q <= write_address_q;
            state_q <= mode_q == BlockRead ? StartRead : BlockData;
          end
        end
        BlockData: if (input_valid && input_ready) begin
          block_data_q[block_index_q[7:0]] <= input_word;
          if (block_index_q + 9'd1 == block_count_q) begin
            block_index_q <= '0;
            state_q <= NextAccess;
          end else block_index_q <= block_index_q + 9'd1;
        end
        NextAccess: begin
          if (mode_q == BlockWrite) write_data_q <= block_data_q[block_index_q[7:0]];
          state_q <= mode_q == BlockRead ? StartRead : StartWrite;
        end
        StartWrite: state_q <= WaitWrite;
        WaitWrite: if (write_done) begin
          output_word_q <= mode_q == Legacy ?
                           (write_status == 0 ? OKAY : ErrorStatus) : {30'b0, write_status};
          state_q <= SendStatus;
        end
        StartRead: state_q <= WaitRead;
        WaitRead: if (read_done) begin
          output_word_q <= read_data;
          read_failed_q <= read_status != 0;
          read_status_q <= read_status;
          state_q <= SendData;
        end
        SendData: if (output_ready) begin
          output_word_q <= mode_q == Legacy ?
                           (read_failed_q ? ErrorStatus : OKAY) : {30'b0, read_status_q};
          state_q <= SendStatus;
        end
        SendStatus: if (output_ready) begin
          if (rx_fault_q) state_q <= Fault;
          else if ((mode_q == BlockRead || mode_q == BlockWrite) &&
                   block_index_q + 9'd1 < block_count_q) begin
            block_index_q <= block_index_q + 9'd1;
            if (!fixed_address_q) begin
              write_address_q <= write_address_q + 32'd4;
              read_address_q <= read_address_q + 32'd4;
            end
            state_q <= NextAccess;
          end else state_q <= Command;
        end
        Fault: ;
        default: state_q <= Command;
      endcase
    end
  end

  data_to_axi #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) bridge (
    .clk(clk), .rst(rst), .r_addr(read_address_q), .r_data(read_data),
    .w_addr(write_address_q), .w_data(write_data_q),
    .start_read(state_q == StartRead), .start_write(state_q == StartWrite),
    .write_done(write_done), .read_done(read_done), .write_status(write_status),
    .read_status(read_status),
    .write_receive(state_q == WaitWrite && write_done),
    .read_receive(state_q == WaitRead && read_done),
    .axi_awaddr(axi_awaddr), .axi_awvalid(axi_awvalid), .axi_awready(axi_awready),
    .axi_wdata(axi_wdata), .axi_wstrb(full_write_strobes), .axi_wvalid(axi_wvalid),
    .axi_wready(axi_wready),
    .axi_bresp(axi_bresp), .axi_bvalid(axi_bvalid), .axi_bready(axi_bready),
    .axi_araddr(axi_araddr), .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
    .axi_rdata(axi_rdata), .axi_rresp(axi_rresp), .axi_rvalid(axi_rvalid), .axi_rready(axi_rready)
  );
  uart_rx #(.BAUD_RATE(BAUD_RATE), .CLK_FREQ(CLK_FREQ), .DATA_WIDTH(UART_DATA_WIDTH)) receiver (
    .clk(clk), .rst(rst), .rx(rx), .mst_data(rx_data), .mst_valid(rx_valid), .mst_ready(rx_ready),
    .framing_error_o(framing_error), .overrun_error_o(overrun_error)
  );
  r_buffer #(.DATA_WIDTH(DATA_WIDTH), .UART_DATA_WIDTH(UART_DATA_WIDTH)) receive_buffer (
    .clk(clk), .rst(rst), .enable(!rx_fault_q), .mst_data(input_word), .mst_valid(input_valid),
    .mst_ready(input_ready), .uart_mst_data(rx_data), .uart_mst_valid(rx_valid),
    .uart_mst_ready(rx_ready)
  );
  t_buffer #(.DATA_WIDTH(DATA_WIDTH), .UART_DATA_WIDTH(UART_DATA_WIDTH)) transmit_buffer (
    .clk(clk), .rst(rst), .enable(1'b1), .slv_data(output_word_q), .slv_valid(output_valid),
    .slv_ready(output_ready), .uart_slv_data(tx_data), .uart_slv_valid(tx_valid),
    .uart_slv_ready(tx_ready)
  );
  uart_tx #(.BAUD_RATE(BAUD_RATE), .CLK_FREQ(CLK_FREQ), .DATA_WIDTH(UART_DATA_WIDTH)) transmitter (
    .clk(clk), .rst(rst), .tx(tx), .slv_data(tx_data), .slv_valid(tx_valid), .slv_ready(tx_ready)
  );
endmodule
