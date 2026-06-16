`timescale 1ns/1ps

//=========================================================
// ADC CONTROLLER
//=========================================================

module adc_controller(
    input clk,
    input sample_tick,
    input [11:0] mux_out,
    output reg [11:0] adc_data
);

always @(posedge clk)
begin

    if(sample_tick)
        adc_data <= mux_out;

end

endmodule
