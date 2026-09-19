# Arty S7-25 and S7-50 (xc7s25csga324-1 / xc7s50csga324-1) - same balls on both. Pins are from Digilent's Arty-S7-25-Master.xdc and were confirmed identical in Arty-S7-50-Master.xdc.
# All six are in bank 15, LVCMOS33.
set_property LOC F14 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property LOC G15 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]
set_property LOC E18 [get_ports led[0]]
set_property IOSTANDARD LVCMOS33 [get_ports led[0]]
set_property LOC F13 [get_ports led[1]]
set_property IOSTANDARD LVCMOS33 [get_ports led[1]]
set_property LOC E13 [get_ports led[2]]
set_property IOSTANDARD LVCMOS33 [get_ports led[2]]
set_property LOC H15 [get_ports led[3]]
set_property IOSTANDARD LVCMOS33 [get_ports led[3]]
