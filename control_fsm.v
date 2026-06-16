`timescale 1ns/1ps

//=========================================================
// CONTROL FSM
//=========================================================

module control_fsm(
    input clk,
    input sample_tick,
    output reg wr_en = 0,
    output reg rd_en = 0
);

reg state = 0;

always @(posedge clk)
begin

    if(sample_tick)
    begin

        case(state)

            1'b0:
            begin
                wr_en <= 1;
                rd_en <= 0;
                state <= 1;
            end

            1'b1:
            begin
                wr_en <= 0;
                rd_en <= 1;
                state <= 0;
            end

        endcase

    end

end

endmodule
