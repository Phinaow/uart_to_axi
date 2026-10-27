module uart_to_cache #(
    parameter bit USE_VENDOR_RAM = 1'b1,
    parameter int BAUD_RATE = 115_200,
    parameter int CPU_CLK_FREQ = 50_000_000
) (
    input logic sys_clk_i,
    input logic sys_rst,

    output logic tx,
    input  logic rx,

    output logic [7:0] led,

    inout  logic [15:0] ddr3_dq,
    inout  logic [ 1:0] ddr3_dqs_n,
    inout  logic [ 1:0] ddr3_dqs_p,
    output logic [14:0] ddr3_addr,
    output logic [ 2:0] ddr3_ba,
    output logic        ddr3_ras_n,
    output logic        ddr3_cas_n,
    output logic        ddr3_we_n,
    output logic        ddr3_reset_n,
    output logic [ 0:0] ddr3_ck_p,
    output logic [ 0:0] ddr3_ck_n,
    output logic [ 0:0] ddr3_cke,
    output logic [ 1:0] ddr3_dm,
    output logic [ 0:0] ddr3_odt
);

  logic [31:0] axi_awaddr;
  logic        axi_awvalid;
  logic        axi_awready;
  logic [31:0] axi_wdata;
  logic        axi_wvalid;
  logic        axi_wready;
  logic [ 3:0] axi_wstrb;
  logic [ 1:0] axi_bresp;
  logic        axi_bvalid;
  logic        axi_bready;
  logic [31:0] axi_araddr;
  logic        axi_arvalid;
  logic        axi_arready;
  logic [31:0] axi_rdata;
  logic [ 1:0] axi_rresp;
  logic        axi_rvalid;
  logic        axi_rready;

  logic        mig_clk_ref;
  logic        clk_cpu;
  logic        clk_mig;
  logic clocks_locked, cpu_reset_n, rx_error, rx_error_sticky;
  logic [31:0] cycle_ct;
  reset_sync uart_reset (.clk_i(clk_cpu), .rst_ni(sys_rst && clocks_locked), .rst_no(cpu_reset_n));
  always_ff @(posedge clk_cpu or negedge cpu_reset_n) begin
    if (!cpu_reset_n) begin
      cycle_ct <= '0;
      rx_error_sticky <= 1'b0;
    end else begin
      cycle_ct <= cycle_ct + 1'b1;
      if (rx_error) rx_error_sticky <= 1'b1;
    end
  end
  assign led = {6'b0, rx_error_sticky, clocks_locked};


  clk_ref_mig clk_mig_inst (
      .clk    (sys_clk_i),
      .reset  (!sys_rst),
      .locked (clocks_locked),
      .clk_ref(mig_clk_ref),
      .clk_cpu(clk_cpu),
      .clk_mig(clk_mig)
  );



  top_cache #(.USE_VENDOR_RAM(USE_VENDOR_RAM)) top_cache_inst (
      .rst_ni       (sys_rst && clocks_locked),
      .clk_mig_i    (clk_mig),
      .clk_ref_i    (mig_clk_ref),
      .clk_cpu_i    (clk_cpu),
      .axi_awaddr_i (axi_awaddr),
      .axi_awvalid_i(axi_awvalid),
      .axi_awready_o(axi_awready),
      .axi_wdata_i  (axi_wdata),
      .axi_wvalid_i (axi_wvalid),
      .axi_wready_o (axi_wready),
      .axi_wstrb_i  (axi_wstrb),
      .axi_bresp_o  (axi_bresp),
      .axi_bvalid_o (axi_bvalid),
      .axi_bready_i (axi_bready),
      .axi_araddr_i (axi_araddr),
      .axi_arvalid_i(axi_arvalid),
      .axi_arready_o(axi_arready),
      .axi_rdata_o  (axi_rdata),
      .axi_rresp_o  (axi_rresp),
      .axi_rvalid_o (axi_rvalid),
      .axi_rready_i (axi_rready),
      .ddr3_dq      (ddr3_dq),
      .ddr3_dqs_n   (ddr3_dqs_n),
      .ddr3_dqs_p   (ddr3_dqs_p),
      .ddr3_addr    (ddr3_addr),
      .ddr3_ba      (ddr3_ba),
      .ddr3_ras_n   (ddr3_ras_n),
      .ddr3_cas_n   (ddr3_cas_n),
      .ddr3_we_n    (ddr3_we_n),
      .ddr3_reset_n (ddr3_reset_n),
      .ddr3_ck_p    (ddr3_ck_p),
      .ddr3_ck_n    (ddr3_ck_n),
      .ddr3_cke     (ddr3_cke),
      .ddr3_dm      (ddr3_dm),
      .ddr3_odt     (ddr3_odt)
  );

  uart_to_axi #(
      .BAUD_RATE(BAUD_RATE),
      .CLK_FREQ(CPU_CLK_FREQ),
      .UART_DATA_WIDTH(8),
      .DATA_WIDTH(32),
      .ADDR_WIDTH(32)
  ) uart_to_axi_inst (
      .clk        (clk_cpu),
      .rst        (!cpu_reset_n),
      .rx         (rx),
      .tx         (tx),
      .axi_awaddr (axi_awaddr),
      .axi_awvalid(axi_awvalid),
      .axi_awready(axi_awready),
      .axi_wdata  (axi_wdata),
      .axi_wvalid (axi_wvalid),
      .axi_wready (axi_wready),
      .axi_wstrb  (axi_wstrb),
      .axi_bresp  (axi_bresp),
      .axi_bvalid (axi_bvalid),
      .axi_bready (axi_bready),
      .axi_araddr (axi_araddr),
      .axi_arvalid(axi_arvalid),
      .axi_arready(axi_arready),
      .axi_rdata  (axi_rdata),
      .axi_rresp  (axi_rresp),
      .axi_rvalid (axi_rvalid),
      .axi_rready (axi_rready),
      .cycle_ct   (cycle_ct),
      .rx_error_o (rx_error)
  );

endmodule
