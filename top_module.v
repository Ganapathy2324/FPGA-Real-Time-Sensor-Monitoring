`timescale 1ns/1ps

//=========================================================
// TOP MODULE
//=========================================================

module top_module(
    input clk,
    input [1:0] sw,

    output [2:0] RGB1,

    output [6:0] D0_SEG,
    output reg [3:0] D0_AN,

    output [6:0] D1_SEG,
    output reg [3:0] D1_AN
);

wire [1:0] sel;
assign sel = sw;

//=========================================================
// SAMPLE TICK
//=========================================================

reg [23:0] div_cnt = 0;
reg sample_tick = 0;

always @(posedge clk)
begin

    if(div_cnt == 24'd10000000)
    begin
        div_cnt <= 0;
        sample_tick <= 1'b1;
    end

    else
    begin
        div_cnt <= div_cnt + 1;
        sample_tick <= 1'b0;
    end

end

//=========================================================
// XADC
//=========================================================

wire [15:0] xadc_data;
wire drdy;
wire [4:0] channel_out;

reg [11:0] temp_data = 0;

xadc_wiz_0 xadc_inst (
.daddr_in(7'd0),
.dclk_in(clk),
.den_in(1'b1),
.di_in(16'd0),
.dwe_in(1'b0),
.reset_in(1'b0),
.busy_out(),
.channel_out(channel_out),
.do_out(xadc_data),
.drdy_out(drdy),
.eoc_out(),
.eos_out(),
.ot_out(),
.vccaux_alarm_out(),
.vccint_alarm_out(),
.user_temp_alarm_out(),
.alarm_out(),
.vp_in(1'b0),
.vn_in(1'b0)
);

//=========================================================
// REAL TEMPERATURE
//=========================================================

always @(posedge clk)
begin

    if(drdy)
    begin

        case(channel_out)

            5'h00:
            temp_data <= ((xadc_data[15:4] * 504) / 4096) - 273;

        endcase

    end

end

//=========================================================
// SENSOR VALUES
//=========================================================

reg [11:0] s0 = 12'd38;
reg [11:0] s1 = 12'd1000;
reg [11:0] s2 = 12'd2500;
reg [11:0] s3 = 12'd3500;

always @(posedge sample_tick)
begin

    s0 <= temp_data;

    if(s1 >= 12'd4000)
        s1 <= 12'd1000;
    else
        s1 <= s1 + 1;

    if(s2 >= 12'd4000)
        s2 <= 12'd2500;
    else
        s2 <= s2 + 2;

    if(s3 >= 12'd4000)
        s3 <= 12'd3500;
    else
        s3 <= s3 + 3;

end

//=========================================================
// THRESHOLD
//=========================================================

reg [11:0] threshold_value;

always @(*)
begin

    case(sel)

        2'b00: threshold_value = 12'd38;
        2'b01: threshold_value = 12'd3000;
        2'b10: threshold_value = 12'd3000;
        2'b11: threshold_value = 12'd3000;

        default: threshold_value = 12'd3000;

    endcase

end

//=========================================================
// INTERNAL SIGNALS
//=========================================================

wire [11:0] mux_out;
wire [11:0] adc_data;
wire [11:0] proc_data;
wire [11:0] fifo_out;

wire wr_en;
wire rd_en;
wire full;
wire empty;

//=========================================================
// MODULE CONNECTIONS
//=========================================================

mux4x1 m1(
.sensor0(s0),
.sensor1(s1),
.sensor2(s2),
.sensor3(s3),
.sel(sel),
.mux_out(mux_out)
);

adc_controller a1(
.clk(clk),
.sample_tick(sample_tick),
.mux_out(mux_out),
.adc_data(adc_data)
);

processing_unit p1(
.clk(clk),
.sample_tick(sample_tick),
.adc_data(adc_data),
.proc_data(proc_data)
);

control_fsm c1(
.clk(clk),
.sample_tick(sample_tick),
.wr_en(wr_en),
.rd_en(rd_en)
);

fifo_buffer f1(
.clk(clk),
.sample_tick(sample_tick),
.wr_en(wr_en),
.rd_en(rd_en),
.din(proc_data),
.dout(fifo_out),
.full(full),
.empty(empty)
);

output_rgb rgb1(
.clk(clk),
.data(fifo_out),
.threshold_value(threshold_value),
.RGB1(RGB1)
);

//=========================================================
// DISPLAY REFRESH
//=========================================================

reg [15:0] refresh_counter = 0;
reg [1:0] digit_select = 0;

always @(posedge clk)
begin

    refresh_counter <= refresh_counter + 1;

    if(refresh_counter == 16'd50000)
    begin
        refresh_counter <= 0;
        digit_select <= digit_select + 1;
    end

end

//=========================================================
// BCD CONVERSION
//=========================================================

wire [3:0] proc_thousands;
wire [3:0] proc_hundreds;
wire [3:0] proc_tens;
wire [3:0] proc_ones;

assign proc_thousands = (fifo_out / 1000) % 10;
assign proc_hundreds  = (fifo_out / 100)  % 10;
assign proc_tens      = (fifo_out / 10)   % 10;
assign proc_ones      =  fifo_out         % 10;

wire [3:0] th_thousands;
wire [3:0] th_hundreds;
wire [3:0] th_tens;
wire [3:0] th_ones;

assign th_thousands = (threshold_value / 1000) % 10;
assign th_hundreds  = (threshold_value / 100)  % 10;
assign th_tens      = (threshold_value / 10)   % 10;
assign th_ones      =  threshold_value         % 10;

//=========================================================
// DISPLAY SELECT
//=========================================================

reg [3:0] left_digit;
reg [3:0] right_digit;

always @(*)
begin

    case(digit_select)

        2'b00:
        begin
            D0_AN = 4'b1110;
            D1_AN = 4'b1110;
            left_digit  = th_ones;
            right_digit = proc_ones;
        end

        2'b01:
        begin
            D0_AN = 4'b1101;
            D1_AN = 4'b1101;
            left_digit  = th_tens;
            right_digit = proc_tens;
        end

        2'b10:
        begin
            D0_AN = 4'b1011;
            D1_AN = 4'b1011;
            left_digit  = th_hundreds;
            right_digit = proc_hundreds;
        end

        2'b11:
        begin
            D0_AN = 4'b0111;
            D1_AN = 4'b0111;
            left_digit  = th_thousands;
            right_digit = proc_thousands;
        end

    endcase

end

//=========================================================
// DISPLAY DRIVERS
//=========================================================

seven_segment disp0(
.digit(left_digit),
.seg(D0_SEG)
);

seven_segment disp1(
.digit(right_digit),
.seg(D1_SEG)
);

endmodule
