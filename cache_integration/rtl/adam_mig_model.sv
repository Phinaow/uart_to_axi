module adam_mig (
    inout [15:0] ddr3_dq,
    inout [1:0] ddr3_dqs_n,
    inout [1:0] ddr3_dqs_p,
    output logic [14:0] ddr3_addr,
    output logic [2:0] ddr3_ba,
    output logic ddr3_ras_n,
    output logic ddr3_cas_n,
    output logic ddr3_we_n,
    output logic ddr3_reset_n,
    output logic [0:0] ddr3_ck_p,
    output logic [0:0] ddr3_ck_n,
    output logic [0:0] ddr3_cke,
    output logic [1:0] ddr3_dm,
    output logic [0:0] ddr3_odt,
    input sys_clk_i,
    input clk_ref_i,
    output logic ui_clk,
    output logic ui_clk_sync_rst,
    output logic ui_addn_clk_0,
    output logic ui_addn_clk_1,
    output logic ui_addn_clk_2,
    output logic ui_addn_clk_3,
    output logic ui_addn_clk_4,
    output logic mmcm_locked,
    input aresetn,
    input app_sr_req,
    input app_ref_req,
    input app_zq_req,
    output logic app_sr_active,
    output logic app_ref_ack,
    output logic app_zq_ack,
    input [1:0] s_axi_awid,
    input [28:0] s_axi_awaddr,
    input [7:0] s_axi_awlen,
    input [2:0] s_axi_awsize,
    input [1:0] s_axi_awburst,
    input [0:0] s_axi_awlock,
    input [3:0] s_axi_awcache,
    input [2:0] s_axi_awprot,
    input [3:0] s_axi_awqos,
    input s_axi_awvalid,
    output logic s_axi_awready,
    input [127:0] s_axi_wdata,
    input [15:0] s_axi_wstrb,
    input s_axi_wlast,
    input s_axi_wvalid,
    output logic s_axi_wready,
    input s_axi_bready,
    output logic [1:0] s_axi_bid,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input [1:0] s_axi_arid,
    input [28:0] s_axi_araddr,
    input [7:0] s_axi_arlen,
    input [2:0] s_axi_arsize,
    input [1:0] s_axi_arburst,
    input [0:0] s_axi_arlock,
    input [3:0] s_axi_arcache,
    input [2:0] s_axi_arprot,
    input [3:0] s_axi_arqos,
    input s_axi_arvalid,
    output logic s_axi_arready,
    input s_axi_rready,
    output logic [1:0] s_axi_rid,
    output logic [127:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rlast,
    output logic s_axi_rvalid,
    output logic init_calib_complete,
    output logic [11:0] device_temp,
    input sys_rst
);

  // Functional AXI substitute for top-level tests; not a DDR3 timing model.
  // Test code may lower this flag to exercise loss of calibration.
  logic test_calibration_enable = 1'b1;
  logic [4:0] startup_q;
  logic [127:0] memory [4096];
  logic write_active_q, read_active_q;
  logic [11:0] write_address_q, read_address_q;
  logic [7:0] write_length_q, read_length_q, write_index_q, read_index_q;
  logic [1:0] write_id_q;

  initial begin
    for (int word = 0; word < 4096; word++) begin
      for (int lane = 0; lane < 16; lane++)
        memory[word][lane*8 +: 8] = 8'((word*16 + lane)*13 + 7);
    end
  end
  assign ui_clk = sys_clk_i;
  assign ui_clk_sync_rst = !sys_rst;
  assign mmcm_locked = sys_rst;
  assign init_calib_complete = startup_q == 20 && test_calibration_enable;
  assign {ui_addn_clk_0, ui_addn_clk_1, ui_addn_clk_2, ui_addn_clk_3, ui_addn_clk_4} = '0;
  assign {app_sr_active, app_ref_ack, app_zq_ack, device_temp} = '0;
  assign {ddr3_addr, ddr3_ba, ddr3_ras_n, ddr3_cas_n, ddr3_we_n,
          ddr3_ck_p, ddr3_ck_n, ddr3_cke, ddr3_dm, ddr3_odt} = '0;
  assign ddr3_reset_n = sys_rst;
  assign s_axi_awready = init_calib_complete && !write_active_q && !s_axi_bvalid;
  assign s_axi_wready = init_calib_complete && write_active_q;
  assign s_axi_arready = init_calib_complete && !read_active_q;
  assign s_axi_rvalid = init_calib_complete && read_active_q;
  assign s_axi_rlast = read_index_q == read_length_q;
  assign s_axi_rresp = 2'b00;

  always_ff @(posedge sys_clk_i or negedge sys_rst) begin
    if (!sys_rst) startup_q <= 0;
    else if (startup_q < 20) startup_q <= startup_q + 1'b1;
  end

  always_ff @(posedge sys_clk_i or negedge sys_rst) begin
    if (!sys_rst) begin
      write_active_q <= 0;
      read_active_q <= 0;
      write_address_q <= 0;
      read_address_q <= 0;
      write_length_q <= 0;
      read_length_q <= 0;
      write_index_q <= 0;
      read_index_q <= 0;
      write_id_q <= 0;
      s_axi_bvalid <= 0;
      s_axi_bresp <= 0;
      s_axi_bid <= 0;
      s_axi_rid <= 0;
      s_axi_rdata <= 0;
    end else if (!init_calib_complete) begin
      write_active_q <= 0;
      read_active_q <= 0;
      s_axi_bvalid <= 0;
    end else begin
      if (s_axi_awvalid && s_axi_awready) begin
        assert (s_axi_awaddr < 65536 && s_axi_awsize == 4 && s_axi_awburst == 1)
          else $fatal(1, "MIG test model supports aligned 128-bit bursts below 64 KiB");
        write_active_q <= 1;
        write_address_q <= s_axi_awaddr[15:4];
        write_length_q <= s_axi_awlen;
        write_index_q <= 0;
        write_id_q <= s_axi_awid;
      end
      if (s_axi_wvalid && s_axi_wready) begin
        assert (s_axi_wlast == (write_index_q == write_length_q)) else $fatal(1, "Bad WLAST");
        for (int lane = 0; lane < 16; lane++) begin
          if (s_axi_wstrb[lane])
            memory[write_address_q + 12'(write_index_q)][lane*8 +: 8] <= s_axi_wdata[lane*8 +: 8];
        end
        if (s_axi_wlast) begin
          write_active_q <= 0;
          s_axi_bvalid <= 1;
          s_axi_bid <= write_id_q;
          s_axi_bresp <= 0;
        end else write_index_q <= write_index_q + 1'b1;
      end
      if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
      if (s_axi_arvalid && s_axi_arready) begin
        assert (s_axi_araddr < 65536 && s_axi_arsize == 4 && s_axi_arburst == 1)
          else $fatal(1, "MIG test model address or burst unsupported");
        read_active_q <= 1;
        read_address_q <= s_axi_araddr[15:4];
        read_length_q <= s_axi_arlen;
        read_index_q <= 0;
        s_axi_rid <= s_axi_arid;
        s_axi_rdata <= memory[s_axi_araddr[15:4]];
      end
      if (s_axi_rvalid && s_axi_rready) begin
        if (s_axi_rlast) read_active_q <= 0;
        else begin
          read_index_q <= read_index_q + 1'b1;
          s_axi_rdata <= memory[read_address_q + 12'(read_index_q) + 1'b1];
        end
      end
    end
  end
endmodule
