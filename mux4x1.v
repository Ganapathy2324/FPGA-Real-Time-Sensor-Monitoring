`timescale 1ns/1ps

//=========================================================
// MUX
//=========================================================

module mux4x1(
    input [11:0] sensor0,
    input [11:0] sensor1,
    input [11:0] sensor2,
    input [11:0] sensor3,
    input [1:0] sel,
    output reg [11:0] mux_out
);

always @(*) begin

    case(sel)

        2'b00: mux_out = sensor0;
        2'b01: mux_out = sensor1;
        2'b10: mux_out = sensor2;
        2'b11: mux_out = sensor3;

        default: mux_out = 12'd0;

    endcase

end

endmodule
