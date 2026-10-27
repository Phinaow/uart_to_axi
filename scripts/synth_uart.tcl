# Standalone synthesis smoke test; no MIG models or board programming.
set root [file normalize [file join [file dirname [info script]] ..]]
set output [file join $root sim_build synthesis]
file mkdir $output
foreach source {uart_rx uart_tx r_buffer t_buffer data_to_axi uart_to_axi} {
    read_verilog -sv [file join $root src ${source}.sv]
}
synth_design -top uart_to_axi -part xc7a200tsbg484-1 -mode out_of_context
create_clock -name clk -period 10.000 [get_ports clk]
report_utilization -file [file join $output utilization.rpt]
report_timing_summary -file [file join $output timing.rpt]
report_cdc -details -file [file join $output cdc.rpt]
report_drc -file [file join $output drc.rpt]
report_bus_skew -file [file join $output bus_skew.rpt]
write_checkpoint -force [file join $output uart_to_axi.dcp]
puts "UART_SYNTHESIS_PASS"
