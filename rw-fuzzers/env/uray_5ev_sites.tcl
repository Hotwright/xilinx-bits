# Site inventory for the ZU5EV die, for prjuray's settings/zynq_usp_5ev.sh.
#
# An earlier pass used 7-series site-type filters and reported "RAMB36 none",
# which is wrong - UltraScale+ names those sites differently. This enumerates
# by actual SITE_TYPE so the ranges in the settings file are derived, not
# assumed.
set part xck26-sfvc784-2LV-c
set out work/uray5ev2
file mkdir $out
link_design -part $part -quiet
set fh [open $out/sites.txt w]
# histogram every site type, with its X/Y extent
array set lo {}; array set hi {}; array set cnt {}
foreach s [get_sites -quiet] {
    set t [get_property SITE_TYPE $s]
    set n [get_property NAME $s]
    if {![regexp {_X(\d+)Y(\d+)$} $n -> x y]} continue
    incr cnt($t)
    if {![info exists lo($t)]} { set lo($t) [list $x $y]; set hi($t) [list $x $y] }
    lassign $lo($t) lx ly; lassign $hi($t) hx hy
    if {$x < $lx} {set lx $x}; if {$y < $ly} {set ly $y}
    if {$x > $hx} {set hx $x}; if {$y > $hy} {set hy $y}
    set lo($t) [list $lx $ly]; set hi($t) [list $hx $hy]
}
foreach t [lsort [array names cnt]] {
    lassign $lo($t) lx ly; lassign $hi($t) hx hy
    puts $fh [format "%-24s %6d  X%dY%d:X%dY%d" $t $cnt($t) $lx $ly $hx $hy]
}
close $fh
# grid extents
set fh [open $out/grid.txt w]
puts $fh "part $part"
puts $fh "grid_x_max [lindex [lsort -integer [get_property COLUMN [get_tiles]]] end]"
puts $fh "grid_y_max [lindex [lsort -integer [get_property ROW [get_tiles]]] end]"
puts $fh "tiles [llength [get_tiles]]"
close $fh
close [open $out/DONE w]
