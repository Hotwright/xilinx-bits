// Basys 3 blinker (XC7A35T-1CPG236C): 100 MHz on W5, BTNC (U18) resets,
// LD0-LD3 count. Pin names and functions are from Digilent's
// Basys-3-Master.xdc; polarities from Digilent's Basys-3-GPIO demo, which
// drives `LED <= SW` and reads its centre button as '1' when pressed.
//
// Same 26-bit counter as the Arty A7's blink.v: same 100 MHz clock, so
// cnt[25] toggles about every 0.34 s.
module top(input clk, input rst, output [3:0] led);
    reg [25:0] cnt = 0;
    always @(posedge clk) cnt <= rst ? 26'd0 : cnt + 1;
    assign led = cnt[25:22];
endmodule
