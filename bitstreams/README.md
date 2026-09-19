# In-house Arty A7-35T bitstream

`arty_a7_35t_blink.bit` — built with **no vendor place-and-route**. Vivado was
not involved in producing it at all.

```
blink.v --yosys(synth_xilinx)--> JSON
        --nextpnr-himbaechel(xilinx)--> FASM
        --prjxray fasm2frames--> frames
        --prjxray xc7frames2bit--> .bit
```

| | |
| --- | --- |
| part | `xc7a35tcsg324-1` (Arty A7-35T) |
| size | 2,192,115 bytes |
| IDCODE | `0x0362d093` (stock xc7a35t) |
| frames | 5408, parses cleanly back through `bitread` |
| timing | 267 MHz (design runs at 100 MHz) |

The design blinks LD4-LD7 from a 26-bit counter on the 100 MHz E3 clock; BTN0
(D9) resets it. Pins were checked against the csg324 package in RapidWright
before use, not taken from memory:

    E3 -> IOB_X1Y76   H5 -> IOB_X1Y51   J5 -> IOB_X1Y50
    D9 -> IOB_X0Y137  T9 -> IOB_X0Y2    T10 -> IOB_X0Y1

## Why this one needed no special handling

nextpnr has a pre-existing `xc7a35t -> xc7a50t` die alias, and prjxray-db ships
a correct `xc7a35tcsg324-1/part.yaml` with the right IDCODE. Contrast the
Blackboard (xc7z007s), which needed both a new alias and a hand-made part.yaml.

## NOT VERIFIED ON HARDWARE

Nothing here has been loaded onto a board. The bitstream is structurally valid
and carries the correct IDCODE, but "it configures and blinks" is unproven.
Program it with openFPGALoader or Vivado's hw_server:

    openFPGALoader -b arty arty_a7_35t_blink.bit
