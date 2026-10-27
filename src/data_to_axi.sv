module data_to_axi #(
    parameter int DATA_WIDTH      = 32         ,
    parameter int ADDR_WIDTH      = 32
) (
    input logic clk,
    input logic rst,

    input logic [ADDR_WIDTH-1:0] r_addr,
    output logic [DATA_WIDTH-1:0] r_data,
    input logic [ADDR_WIDTH-1:0] w_addr,
    input logic [DATA_WIDTH-1:0] w_data,

    input logic start_read,
    input logic start_write,
    output logic write_done,
    output logic read_done,
    output logic [1:0] write_status,
    output logic [1:0] read_status,
    input logic write_receive,
    input logic read_receive,

    // --- //
    // AXI //
    // --- //
    // --------------- //
    // Write interface //
    // --------------- //
    // Addr signals
    output logic [ADDR_WIDTH-1:0] axi_awaddr ,
    output logic                  axi_awvalid,
    input  logic                  axi_awready,
    // Data signals
    output logic [DATA_WIDTH-1:0] axi_wdata  ,
    output logic                  axi_wvalid ,
    input  logic                  axi_wready ,
    output logic [DATA_WIDTH/8-1:0] axi_wstrb,
    input logic [1:0] axi_bresp,
    input logic axi_bvalid,
    output logic axi_bready,
    // -------------- //
    // Read interface //
    // -------------- //
    // Addr signals
    output logic [ADDR_WIDTH-1:0] axi_araddr ,
    output logic                  axi_arvalid,
    input  logic                  axi_arready,
    // Data signals
    input  logic [DATA_WIDTH-1:0] axi_rdata  ,
    input  logic                  axi_rvalid ,
    input logic [1:0] axi_rresp,
    output logic                  axi_rready
);

    typedef enum logic [1:0] {WriteIdle, WriteTransfer, WriteResponse, WriteDone} write_state_t;
    typedef enum logic [1:0] {ReadIdle, ReadAddress, ReadData, ReadDone} read_state_t;
    write_state_t write_state_q;
    read_state_t read_state_q;
    logic [ADDR_WIDTH-1:0] write_address_q, read_address_q;
    logic [DATA_WIDTH-1:0] write_data_q;
    logic address_sent_q, data_sent_q;

    assign axi_awaddr = write_address_q;
    assign axi_wdata = write_data_q;
    assign axi_wstrb = '1;
    assign axi_awvalid = !rst && write_state_q == WriteTransfer && !address_sent_q;
    assign axi_wvalid = !rst && write_state_q == WriteTransfer && !data_sent_q;
    assign axi_bready = !rst && write_state_q == WriteResponse;
    assign write_done = !rst && write_state_q == WriteDone;
    assign axi_araddr = read_address_q;
    assign axi_arvalid = !rst && read_state_q == ReadAddress;
    assign axi_rready = !rst && read_state_q == ReadData;
    assign read_done = !rst && read_state_q == ReadDone;

    // Each request remains stable until its independent AXI handshake.
    assert property (@(posedge clk) disable iff (rst)
      axi_awvalid && !axi_awready |=> axi_awvalid && $stable(axi_awaddr));
    assert property (@(posedge clk) disable iff (rst)
      axi_wvalid && !axi_wready |=> axi_wvalid && $stable({axi_wdata, axi_wstrb}));
    assert property (@(posedge clk) disable iff (rst)
      axi_arvalid && !axi_arready |=> axi_arvalid && $stable(axi_araddr));
    assert property (@(posedge clk) disable iff (rst)
      write_done && !write_receive |=> write_done && $stable(write_status));
    assert property (@(posedge clk) disable iff (rst)
      read_done && !read_receive |=> read_done && $stable({r_data, read_status}));

    always_ff @(posedge clk) begin
      if (rst) begin
        write_state_q <= WriteIdle;
        read_state_q <= ReadIdle;
        write_address_q <= '0;
        read_address_q <= '0;
        write_data_q <= '0;
        address_sent_q <= 1'b0;
        data_sent_q <= 1'b0;
        r_data <= '0;
        write_status <= '0;
        read_status <= '0;
      end else begin
        case (write_state_q)
          WriteIdle: if (start_write) begin
            write_address_q <= w_addr;
            write_data_q <= w_data;
            address_sent_q <= 1'b0;
            data_sent_q <= 1'b0;
            write_state_q <= WriteTransfer;
          end
          WriteTransfer: begin
            if (axi_awvalid && axi_awready) address_sent_q <= 1'b1;
            if (axi_wvalid && axi_wready) data_sent_q <= 1'b1;
            if ((address_sent_q || axi_awready) && (data_sent_q || axi_wready))
              write_state_q <= WriteResponse;
          end
          WriteResponse: if (axi_bvalid) begin
            write_status <= axi_bresp;
            write_state_q <= WriteDone;
          end
          WriteDone: if (write_receive) write_state_q <= WriteIdle;
          default: write_state_q <= WriteIdle;
        endcase
        case (read_state_q)
          ReadIdle: if (start_read) begin
            read_address_q <= r_addr;
            read_state_q <= ReadAddress;
          end
          ReadAddress: if (axi_arready) read_state_q <= ReadData;
          ReadData: if (axi_rvalid) begin
            r_data <= axi_rdata;
            read_status <= axi_rresp;
            read_state_q <= ReadDone;
          end
          ReadDone: if (read_receive) read_state_q <= ReadIdle;
          default: read_state_q <= ReadIdle;
        endcase
      end
    end
endmodule
