`timescale 1ns/1ps

//=========================================================
// FIFO BUFFER
//=========================================================

module fifo_buffer(
    input clk,
    input sample_tick,
    input wr_en,
    input rd_en,
    input [11:0] din,
    output reg [11:0] dout,
    output full,
    output empty
);

reg [11:0] mem [0:15];

reg [3:0] w_ptr = 0;
reg [3:0] r_ptr = 0;
reg [4:0] count = 0;

assign full  = (count == 16);
assign empty = (count == 0);

always @(posedge clk)
begin

    if(sample_tick)
    begin

        if(wr_en && !full)
        begin
            mem[w_ptr] <= din;
            w_ptr <= w_ptr + 1;
        end

        if(rd_en && !empty)
        begin
            dout <= mem[r_ptr];
            r_ptr <= r_ptr + 1;
        end

        case({wr_en && !full, rd_en && !empty})

            2'b10: count <= count + 1;
            2'b01: count <= count - 1;
            default: count <= count;

        endcase

    end

end

endmodule
