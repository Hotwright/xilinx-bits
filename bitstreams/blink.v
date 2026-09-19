// Arty A7-35T blinker: 100 MHz on E3, BTN0 (D9) resets, LD4-LD7 count.
module top(input clk, input rst, output [3:0] led);
    reg [25:0] cnt = 0;
    always @(posedge clk) cnt <= rst ? 26'd0 : cnt + 1;
    assign led = cnt[25:22];
endmodule
