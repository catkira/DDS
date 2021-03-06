`timescale 1ns / 1ns

module dds
/*********************************************************************************************/
#(
    parameter PHASE_DW = 16,          // phase data width
    parameter OUT_DW = 16,            // output data width
    parameter USE_TAYLOR = 0,         // use taylor approximation
    parameter LUT_DW = 10,            // width of sine lut if taylor approximation is used
    parameter SIN_COS = 0             // set to 1 if cos output in addition to sin output is desired
)
/*********************************************************************************************/
(
    input                                   clk,
    input                                   reset_n,
    input   wire  unsigned [PHASE_DW-1:0]   s_axis_phase_tdata,
    input                                   s_axis_phase_tvalid,
    output  wire    signed [OUT_DW-1:0]     m_axis_out_sin_tdata,
    output                                  m_axis_out_sin_tvalid,
    output  wire    signed [OUT_DW-1:0]     m_axis_out_cos_tdata,
    output                                  m_axis_out_cos_tvalid
);
/*********************************************************************************************/
// architecture for USE_TAYLOR = 0 is similar as in https://zipcpu.com/dsp/2017/08/26/quarterwave.html
// lut file is compatible to zipcpu lut file

localparam EFFECTIVE_LUT_WIDTH = USE_TAYLOR ? LUT_DW : PHASE_DW - 2;
localparam PI_HALF = (2**PHASE_DW)/4;
localparam PHASE_ERROR_WIDTH = USE_TAYLOR ? PHASE_DW - (LUT_DW - 2) : 1;

reg signed [OUT_DW - 1 : 0] lut [0 : 2**EFFECTIVE_LUT_WIDTH - 1];
initial	begin
    $readmemh("../../hdl/sine_lut.hex", lut);
    if (USE_TAYLOR) begin
        if (LUT_DW > PHASE_DW - 2) begin
            $display("LUT_DW > PHASE_DW - 2 does not make sense!");
        end
    end
end

// input buffer, stage 1
reg unsigned [PHASE_DW - 1 : 0] phase_buf;
reg in_valid_buf;
always_ff @(posedge clk) begin
    phase_buf <= !reset_n ? 0 : (s_axis_phase_tvalid ? s_axis_phase_tdata : phase_buf);
    in_valid_buf <= !reset_n ? 0 : s_axis_phase_tvalid;
end

// calculate lut index, stage 2
reg in_valid_buf2;
reg unsigned [EFFECTIVE_LUT_WIDTH-1:0] sin_lut_index, cos_lut_index;
reg unsigned [PHASE_ERROR_WIDTH-1:0] phase_error;
reg unsigned [1:0] sin_quadrant_index;
always_ff @(posedge clk) begin
    in_valid_buf2 <= !reset_n ? 0 : in_valid_buf;
    sin_quadrant_index <= !reset_n ? 0 : phase_buf[PHASE_DW-1:PHASE_DW-2];
    // sin
    if (phase_buf[PHASE_DW - 2]) // if in 2nd or 4th quadrant
        sin_lut_index <= !reset_n ? 0 : ~phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH] + 1;
    else
        sin_lut_index <= !reset_n ? 0 : phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH];
    // cos
    if (SIN_COS || USE_TAYLOR) begin
        if (!phase_buf[PHASE_DW - 2]) // if in 1st or 3rd quadrant
            cos_lut_index <= !reset_n ? 0 : ~phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH] + 1;
        else
            cos_lut_index <= !reset_n ? 0 : phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH];
    end

    if (USE_TAYLOR) begin
        phase_error <= !reset_n ? 0 : phase_buf[PHASE_ERROR_WIDTH - 1: 0];
    end
end

// lut reading, stage 3
reg in_valid_buf3;
reg signed [OUT_DW-1:0] sin_lut_data, cos_lut_data;
reg unsigned [1:0] sin_quadrant_index2;
reg unsigned [PHASE_ERROR_WIDTH-1:0] phase_error2;
always_ff @(posedge clk) begin
    in_valid_buf3 <= !reset_n ? 0 : in_valid_buf2;
    // sin
    sin_quadrant_index2 <= !reset_n ? 0 : sin_quadrant_index;
    if (sin_quadrant_index[0] && sin_lut_index == 0)
        sin_lut_data <= !reset_n ? 0 : 2**(OUT_DW-1) - 1;
    else
        sin_lut_data <= !reset_n ? 0 : lut[sin_lut_index];
    // cos
    if (SIN_COS || USE_TAYLOR) begin
        if (!sin_quadrant_index[0] && cos_lut_index == 0)
            cos_lut_data <= !reset_n ? 0 : 2**(OUT_DW-1) - 1;
        else
            cos_lut_data <= !reset_n ? 0 :  lut[cos_lut_index];
    end

    if (USE_TAYLOR)
        phase_error2 <= !reset_n ? 0 : phase_error;
    // debug stuff
    if(in_valid_buf2) begin
        // $display("lut[%d] = %d",sin_lut_index, sin_lut_data);
        // $display("lut[%d] = %d",cos_lut_index, cos_lut_data);
    end
end

// output buffer, stage 4
reg signed [OUT_DW - 1 : 0] out_sin_buf;
reg signed [OUT_DW - 1 : 0] out_cos_buf;
reg unsigned [PHASE_ERROR_WIDTH-1:0] phase_error3;
reg out_valid_buf;
always_ff @(posedge clk) begin
    if (sin_quadrant_index2[1]) // if in 3rd or 4th quadrant
        out_sin_buf <= !reset_n ? 0 : -sin_lut_data;
    else
        out_sin_buf <= !reset_n ? 0 : sin_lut_data;
    if (SIN_COS || USE_TAYLOR) begin
        if (sin_quadrant_index2 == 2'b10 || sin_quadrant_index2 == 2'b01) // if in 2nd or 3rd quadrant
            out_cos_buf <= !reset_n ? 0 : -cos_lut_data;
        else
            out_cos_buf <= !reset_n ? 0 : cos_lut_data;
    end
    if (USE_TAYLOR)
        phase_error3 <= !reset_n ? 0 : phase_error2;
    out_valid_buf <= !reset_n ? 0 : in_valid_buf3;    
end

// taylor correction, stage 5
reg signed [OUT_DW - 1 : 0] out_sin_buf2;
reg signed [OUT_DW - 1 : 0] out_cos_buf2;
reg out_valid_buf2;
wire signed [PHASE_ERROR_WIDTH:0] phase_error_signed;
assign phase_error_signed = {1'b0, phase_error3};

localparam EXTENDED_WIDTH = OUT_DW + PHASE_ERROR_WIDTH;
wire signed [EXTENDED_WIDTH - 1 : 0] sin_extended, cos_extended;
wire signed [EXTENDED_WIDTH - 1 : 0] sin_corrected, cos_corrected;
assign sin_extended = {out_sin_buf, {(PHASE_ERROR_WIDTH){1'b0}}};
assign sin_corrected = sin_extended + out_cos_buf * phase_error_signed;
assign cos_extended = {out_cos_buf, {(PHASE_ERROR_WIDTH){1'b0}}};
assign cos_corrected = cos_extended + out_sin_buf * phase_error_signed;
always_ff @(posedge clk) begin
    if (out_valid_buf && USE_TAYLOR) begin
        //$display("sin_phase_error * cos = %d * %d = %d", phase_error_signed, out_cos_buf, out_cos_buf * phase_error_signed);
        //$display("corrected = %d  uncorrected = %d", sin_corrected, sin_extended);
        // $display("cos_phase_error * sin = %d * %d = %d", phase_error_signed, out_sin_buf, out_sin_buf * phase_error_signed);
        // $display("corrected = %d  uncorrected = %d", cos_corrected[EXTENDED_WIDTH - 1 -: OUT_DW], cos_extended[EXTENDED_WIDTH - 1 -: OUT_DW]);
    end
    out_sin_buf2 <= sin_corrected[EXTENDED_WIDTH - 1 -: OUT_DW];
    out_cos_buf2 <= cos_corrected[EXTENDED_WIDTH - 1 -: OUT_DW];
    out_valid_buf2 <= !reset_n ? 0 : out_valid_buf;    
end

if (USE_TAYLOR) begin
    assign m_axis_out_sin_tdata = out_sin_buf2;
    assign m_axis_out_sin_tvalid = out_valid_buf2;
    assign m_axis_out_cos_tdata = out_cos_buf2;
    assign m_axis_out_cos_tvalid = out_valid_buf2;    
end
else begin
    assign m_axis_out_sin_tdata = out_sin_buf;
    assign m_axis_out_sin_tvalid = out_valid_buf;
    assign m_axis_out_cos_tdata = out_cos_buf;
    assign m_axis_out_cos_tvalid = out_valid_buf;
end

endmodule