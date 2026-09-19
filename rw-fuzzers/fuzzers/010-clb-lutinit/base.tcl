# Step A baseline: prjxray fuzzers/010-clb-lutinit/generate.tcl, truncated.
#
# Everything up to and including the first (unmodified) bitstream is kept, so
# this produces both the base checkpoint that the RapidWright generator mutates
# and the Vivado ground truth that its output is diffed against. The INIT
# permutation passes are gone - that is what RapidWright now does.
create_project -force -part $::env(XRAY_PART) design design

# Absolute, via the environment: the specimen directory sits at a
# fuzzer-relative depth that has changed once already, and a relative path here
# fails silently into "file does not exist".
read_verilog $::env(FUZDIR)/top.v
synth_design -top top

set_property -dict "PACKAGE_PIN $::env(XRAY_PIN_00) IOSTANDARD LVCMOS33" [get_ports clk]
set_property -dict "PACKAGE_PIN $::env(XRAY_PIN_01) IOSTANDARD LVCMOS33" [get_ports di]
set_property -dict "PACKAGE_PIN $::env(XRAY_PIN_02) IOSTANDARD LVCMOS33" [get_ports do]
set_property -dict "PACKAGE_PIN $::env(XRAY_PIN_03) IOSTANDARD LVCMOS33" [get_ports stb]

# Identity pin mapping. Without this the netlist INIT and the physical LUT
# contents differ by a pin permutation and every INIT tag would be wrong.
set_property LOCK_PINS {I0:A1 I1:A2 I2:A3 I3:A4 I4:A5 I5:A6} \
        [get_cells -quiet -filter {REF_NAME == LUT6} -hierarchical]

# Not every config defines an ROI: artix7_200t characterises the whole device.
# With no pblock the LUTs simply spread over the whole fabric, which is fine
# here - segmaker works from whichever tiles actually ended up with LUTs.
if {[info exists ::env(XRAY_ROI)] && [string trim $::env(XRAY_ROI)] ne ""} {
    create_pblock roi
    add_cells_to_pblock [get_pblocks roi] [get_cells roi]
    resize_pblock [get_pblocks roi] -add "$::env(XRAY_ROI)"
} else {
    puts "XRAY_ROI unset - placing over the whole device."
}

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.PERFRAMECRC YES [current_design]
set_param tcl.collectionResultDisplayLimit 0

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_IBUF]

place_design
route_design

write_checkpoint -force design.dcp

# RapidWright cannot read the encrypted EDIF that Vivado embeds in a DCP; it
# would otherwise shell out to Vivado itself to convert it, which cannot work
# here (there is no Linux Vivado). Exporting readable EDIF alongside the
# checkpoint lets RapidWright open the pair directly.
write_edif -force design.edf

proc write_txtdata {filename} {
    puts "Writing $filename."
    set fp [open $filename w]
    foreach cell [get_cells -hierarchical -filter {REF_NAME == LUT6}] {
        set bel [get_property BEL $cell]
        set loc [get_property LOC $cell]
        set init [get_property INIT $cell]
        puts $fp "$loc $bel $init"
    }
    close $fp
}

write_bitstream -force design_0_vivado.bit
write_txtdata design_0_vivado.txt
