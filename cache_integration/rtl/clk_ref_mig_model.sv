// Functional clock-wizard substitute for board-top tests; no frequency synthesis.
module clk_ref_mig (
    input logic clk,
    input logic reset,
    output logic locked,
    output logic clk_ref,
    output logic clk_cpu,
    output logic clk_mig
);
  assign locked = !reset;
  assign clk_ref = clk;
  assign clk_cpu = clk;
  assign clk_mig = clk;
endmodule
