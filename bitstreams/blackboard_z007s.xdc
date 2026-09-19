# Blackboard (Zynq Z-7007S, xc7z007sclg400-1). Pins as used by the earlier
# Vivado reference run in rw-fuzzers/work/z007s_ref/ref.tcl: 100 MHz PL clock on
# H16, BTN0 on W14 (active high), LD0-LD3 on N20/P20/R19/T20.
set_property LOC H16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property LOC W14 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]
set_property LOC N20 [get_ports led[0]]
set_property IOSTANDARD LVCMOS33 [get_ports led[0]]
set_property LOC P20 [get_ports led[1]]
set_property IOSTANDARD LVCMOS33 [get_ports led[1]]
set_property LOC R19 [get_ports led[2]]
set_property IOSTANDARD LVCMOS33 [get_ports led[2]]
set_property LOC T20 [get_ports led[3]]
set_property IOSTANDARD LVCMOS33 [get_ports led[3]]
