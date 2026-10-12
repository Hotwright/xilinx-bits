# XCK26 IO/clock survey, for the prjuray scoping question.
#
# prjuray-db's zynqusp data was fuzzed on a ZU3EG. The XCK26 is a ZU5EV, and a
# tile-type census showed 88 of its 195 tile types have no tile_type_*.json at
# all - among them the ENTIRE LEFT IO COLUMN (HPIO_L, INT_INTF_L_IO,
# XIPHY_BYTE_L) and all six URAM_* types. prjuray-db carries HPIO_RIGHT only.
#
# Three questions that decide whether a PL-only blinky is reachable on existing
# data, or needs its own fuzz run:
#   1. which tile type do the K26's user IO pads actually sit on, by bank
#   2. is HPIO_L structurally the same as HPIO_RIGHT (if not, no transfer is
#      even conceivable - prjxray keeps liob33/riob33 separate on 7-series,
#      so mirrored IO columns are measured, not assumed)
#   3. which package pins are clock-capable, and on which tile type
set part xck26-sfvc784-2LV-c
set out [expr {[info exists ::env(K26_OUT)] ? $::env(K26_OUT) : "work/k26pins"}]
file mkdir $out
link_design -part $part -quiet

# --- 1. every user IO pin -> site -> tile -> tile type, with its bank
set fh [open $out/pins.txt w]
foreach p [get_package_pins -quiet] {
    set site [get_sites -quiet -of_objects $p]
    if {$site eq ""} continue
    set st [get_property SITE_TYPE [get_sites $site]]
    if {![regexp {^(IOB|HPIOB|HDIOB|IPAD|OPAD)} $st]} continue
    set tile [get_tiles -quiet -of_objects [get_sites $site]]
    if {$tile eq ""} continue
    puts $fh "[get_property NAME $p] $site $st $tile [get_property TILE_TYPE [get_tiles $tile]] [get_property BANK $p]"
}
close $fh

# --- 2. structure of one HPIO_L tile vs one HPIO_RIGHT-equivalent, if present
set fh [open $out/hpio_sites.txt w]
foreach tt {HPIO_L HPIO_RIGHT HPIO_R HDIO_BOT_RIGHT HDIO_TOP_RIGHT} {
    set tiles [get_tiles -quiet -filter "TILE_TYPE == $tt"]
    if {[llength $tiles] == 0} continue
    set t [lindex [lsort $tiles] 0]
    puts $fh "# $tt : [llength $tiles] tiles, sample $t"
    foreach s [lsort [get_sites -quiet -of_objects [get_tiles $t]]] {
        puts $fh "$tt [get_property SITE_TYPE [get_sites $s]]"
    }
}
close $fh

# --- 3. clock-capable pins. Property name discovered, never guessed.
set props [list_property [lindex [get_package_pins] 0]]
set fh [open $out/pinprops.txt w]; puts $fh $props; close $fh
set ccprop ""
foreach cand {IS_CLK_CAPABLE IS_GLOBAL_CLK CLOCK_CAPABLE IS_CLOCK_CAPABLE} {
    if {[lsearch -exact $props $cand] >= 0} { set ccprop $cand; break }
}
set fh [open $out/clkpins.txt w]
puts $fh "# clock-capable property: [expr {$ccprop eq "" ? "NONE FOUND" : $ccprop}]"
if {$ccprop ne ""} {
    foreach p [get_package_pins -quiet] {
        set site [get_sites -quiet -of_objects $p]
        if {$site eq ""} continue
        if {[get_property $ccprop $p] != 1} continue
        set tile [get_tiles -quiet -of_objects [get_sites $site]]
        if {$tile eq ""} continue
        puts $fh "[get_property NAME $p] $site $tile [get_property TILE_TYPE [get_tiles $tile]] bank[get_property BANK $p]"
    }
}
close $fh
close [open $out/DONE w]
