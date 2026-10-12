# One short Vivado run per die: everything needed to decide whether a die is a
# new fabric or an alias of one already built, and to write its settings file.
#
# Deliberately cheap - link_design on an empty netlist, no synthesis, no
# placement. The expensive parts of characterisation come later and only for
# dies this pass says are actually new.
set part $::env(CENSUS_PART)
set out  $::env(CENSUS_OUT)

# A part Vivado cannot open is the licence/install census for free: record the
# reason rather than dying, so one bad part does not stop the sweep.
if {[llength [get_parts -quiet $part]] == 0} {
    set f [open ${out}/ERROR w]; puts $f "part not available in this install"; close $f
    exit 0
}
if {[catch {link_design -part $part} err]} {
    set f [open ${out}/ERROR w]; puts $f "link_design failed: $err"; close $f
    exit 0
}

set f [open ${out}/part.txt w]
puts $f "part [get_property NAME [get_parts $part]]"
puts $f "family [get_property FAMILY [get_parts $part]]"
puts $f "device [get_property DEVICE [get_parts $part]]"
puts $f "package [get_property PACKAGE [get_parts $part]]"
puts $f "speed [get_property SPEED [get_parts $part]]"
puts $f "idcode [get_property IDCODE [get_parts $part]]"
puts $f "slices [get_property SLICES [get_parts $part]]"
puts $f "luts [get_property LUT_ELEMENTS [get_parts $part]]"
puts $f "ffs [get_property FLIPFLOPS [get_parts $part]]"
puts $f "brams [get_property BLOCK_RAMS [get_parts $part]]"
puts $f "dsps [get_property DSP [get_parts $part]]"
close $f

# The fabric signature. This is the same comparison that established
# xc7z007s -> xc7z010: every tile's name, type and grid position. Two dies whose
# signature files are identical share a fabric and one chipdb serves both.
set f [open ${out}/tiles.txt w]
foreach t [lsort [get_tiles]] {
    puts $f "[get_property NAME $t] [get_property TYPE $t] [get_property COLUMN $t] [get_property ROW $t]"
}
close $f

# Inputs for the per-die settings file.
set f [open ${out}/ioi3.txt w]
foreach t [lsort [get_tiles -filter {TYPE =~ *IOI3*}]] { puts $f "[get_property NAME $t] [get_property TYPE $t]" }
close $f

set f [open ${out}/clkpins.txt w]
foreach p [lsort [get_package_pins -quiet -filter {IS_CLK_CAPABLE}]] {
    puts $f "[get_property NAME $p] [get_property IS_CLK_CAPABLE $p]"
}
close $f

set f [open ${out}/extents.txt w]
puts $f "columns [llength [lsort -unique [get_property COLUMN [get_tiles]]]]"
puts $f "rows [llength [lsort -unique [get_property ROW [get_tiles]]]]"
puts $f "tiles [llength [get_tiles]]"
puts $f "nodes [llength [get_nodes -quiet]]"
close $f

set f [open ${out}/DONE w]; puts $f ok; close $f
