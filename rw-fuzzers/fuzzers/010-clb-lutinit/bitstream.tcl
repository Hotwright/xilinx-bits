# Turn a checkpoint into a bitstream. This is the only Vivado step the
# RapidWright flow still needs.
#
# The variant name is passed via -tclargs rather than the environment so that
# nothing has to cross the WSL/Windows boundary beyond the file itself.
set variant [lindex $argv 0]

open_checkpoint design_${variant}.dcp

# Re-assert the design-level properties write_bitstream requires. Whether
# RapidWright preserves these through a checkpoint round trip is exactly what
# Step B measures; setting them here is cheap insurance either way.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.PERFRAMECRC YES [current_design]

write_bitstream -force design_${variant}.bit
