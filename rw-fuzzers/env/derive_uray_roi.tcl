# Derive the die-specific parts of a prjuray settings file.
#
# URAY_ROI_GRID_{X1,X2,Y1,Y2} bound the tile-grid region the fuzzers work in,
# and URAY_PIN_00..03 are four user IO used to drive test designs. Everything
# else in a settings file is either fixed (URAY_ROI_FRAMES is the whole device
# in both shipped examples) or a part name.
set part $::env(URAY_PART_IN)
set out  $::env(URAY_OUT)

if {[catch {link_design -part $part} err]} {
    set f [open ${out}/ERROR w]; puts $f "link_design failed: $err"; close $f
    exit 0
}

set f [open ${out}/roi.txt w]
puts $f "part $part"

# Tile grid bounds.
set cols {}; set rows {}
foreach t [get_tiles] {
    lappend cols [get_property COLUMN $t]
    lappend rows [get_property ROW $t]
}
set cols [lsort -integer $cols]; set rows [lsort -integer $rows]
puts $f "grid_x_min [lindex $cols 0]"
puts $f "grid_x_max [lindex $cols end]"
puts $f "grid_y_min [lindex $rows 0]"
puts $f "grid_y_max [lindex $rows end]"

# Site ranges per type, for the ROI strings the shipped settings carry.
foreach st {SLICE DSP48E2 RAMB18 RAMB36 URAM288} {
    set sites [get_sites -quiet -filter "SITE_TYPE =~ ${st}*"]
    if {[llength $sites] == 0} { puts $f "sites_${st} none"; continue }
    set xs {}; set ys {}
    foreach s $sites {
        if {[regexp {_X(\d+)Y(\d+)$} [get_property NAME $s] -> x y]} {
            lappend xs $x; lappend ys $y
        }
    }
    set xs [lsort -integer $xs]; set ys [lsort -integer $ys]
    puts $f "sites_${st} [llength $sites] X[lindex $xs 0]Y[lindex $ys 0]:X[lindex $xs end]Y[lindex $ys end]"
}
close $f

# Candidate pins: ordinary user IO in one bank, and whether the pins the 3EG
# settings use exist here too (same SFVC784 package, different die).
set f [open ${out}/pins.txt w]
foreach want {E12 C12 D12 A11} {
    set p [get_package_pins -quiet $want]
    if {[llength $p] == 0} {
        puts $f "$want ABSENT"
    } else {
        set site [get_sites -quiet -of_objects $p]
        puts $f "$want present site=[get_property NAME $site] bank=[get_property BANK $p] type=[get_property PIN_FUNC $p]"
    }
}
puts $f "---candidates---"
set n 0
foreach p [lsort [get_package_pins -quiet -filter {IS_GENERAL_PURPOSE}]] {
    set site [get_sites -quiet -of_objects $p]
    if {[llength $site] == 0} { continue }
    puts $f "[get_property NAME $p] site=[get_property NAME $site] bank=[get_property BANK $p]"
    incr n
    if {$n >= 12} { break }
}
close $f
set f [open ${out}/DONE w]; puts $f ok; close $f
