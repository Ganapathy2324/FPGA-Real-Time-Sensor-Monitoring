`timescale 1ns/1ps

//=========================================================
// PROCESSING UNIT
//=========================================================

module processing_unit(
    input clk,
    input sample_tick,
    input [11:0] adc_data,
    output reg [11:0] proc_data
);

reg [11:0] prev = 0;
reg [12:0] sum;

always @(posedge clk)
begin

    if(sample_tick)
    begin

        sum = adc_data + prev;
        proc_data <= sum >> 1;
        prev <= adc_data;

    end

end

endmodule
