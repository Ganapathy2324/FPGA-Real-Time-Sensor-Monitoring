`timescale 1ns/1ps

//=========================================================
// RGB OUTPUT
//=========================================================

module output_rgb(
    input clk,
    input [11:0] data,
    input [11:0] threshold_value,
    output reg [2:0] RGB1 = 3'b111
);

reg [25:0] blink_counter = 0;
reg blink = 0;

always @(posedge clk)
begin

    if(blink_counter == 26'd5000000)
    begin
        blink_counter <= 0;
        blink <= ~blink;
    end

    else
    begin
        blink_counter <= blink_counter + 1;
    end

end

always @(posedge clk)
begin

    // BELOW THRESHOLD -> GREEN
    if(data < threshold_value)
    begin
        RGB1 <= 3'b011;
    end

    // EQUAL THRESHOLD -> YELLOW
    else if(data == threshold_value)
    begin
        RGB1 <= 3'b010;
    end

    // ABOVE THRESHOLD -> RED BLINK
    else
    begin
        if(blink)
            RGB1 <= 3'b110;
        else
            RGB1 <= 3'b111;
    end

end

endmodule
