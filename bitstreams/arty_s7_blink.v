// Arty S7 blinker (S7-25 and S7-50 use the same balls): 12 MHz on F14 (the uclk oscillator), BTN0 (G15) resets,
// LD2-LD5 count. Pin names and functions are from Digilent's
// Arty-S7-25-Master.xdc; the sites they land on were resolved through this
// tree's own xc7s25csga324-1/package_pins.csv.
//
// The counter is 24 bits rather than the A7 design's 26 because this board
// clocks at 12 MHz, not 100 MHz: cnt[23] toggles about every 0.7 s.
module top(input clk, input rst, output [3:0] led);
    reg [23:0] cnt = 0;
    always @(posedge clk) cnt <= rst ? 24'd0 : cnt + 1;
    assign led = cnt[23:20];
endmodule
