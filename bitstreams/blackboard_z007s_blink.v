// Minimal Blackboard-shaped design: 100 MHz PL clock (H16), BTN0 reset (W14,
// active high), driving the four LEDs.
module top(input clk, input rst, output [3:0] led);
    reg [25:0] cnt = 0;
    always @(posedge clk) begin
        if (rst) cnt <= 0;
        else     cnt <= cnt + 1;
    end
    assign led = cnt[25:22];
endmodule
