`timescale 1ns / 1ns

module dds
/*********************************************************************************************/
#(
    parameter PHASE_DW = 16,          // phase data width
    parameter OUT_DW = 16,            // output data width
    parameter USE_TAYLOR = 0,         // use taylor approximation
    parameter LUT_WIDTH = 10,         // width of sine lut if taylor approximation is used
    parameter SIN_COS = 0
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

localparam EFFECTIVE_LUT_WIDTH = USE_TAYLOR ? LUT_WIDTH : PHASE_DW - 2;
localparam PI_HALF = (2**PHASE_DW)/4;

reg signed [OUT_DW - 1 : 0] lut [0 : 2**EFFECTIVE_LUT_WIDTH - 1];
initial	begin
    $readmemh("../../hdl/sine_lut.hex", lut);
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
reg unsigned [1:0] sin_quadrant_index, cos_quadrant_index;
wire [PHASE_DW-1:0] cos_phase;
assign cos_phase = phase_buf + PI_HALF;
always_ff @(posedge clk) begin
    in_valid_buf2 <= !reset_n ? 0 : in_valid_buf;
    sin_quadrant_index <= !reset_n ? 0 : phase_buf[EFFECTIVE_LUT_WIDTH+1:EFFECTIVE_LUT_WIDTH];
    cos_quadrant_index <= !reset_n ? 0 : cos_phase[EFFECTIVE_LUT_WIDTH+1:EFFECTIVE_LUT_WIDTH];
    if (phase_buf[EFFECTIVE_LUT_WIDTH])
        sin_lut_index <= !reset_n ? 0 : ~phase_buf[EFFECTIVE_LUT_WIDTH - 1 : 0];
    else
        sin_lut_index <= !reset_n ? 0 : phase_buf[EFFECTIVE_LUT_WIDTH - 1 : 0];
    if (SIN_COS) begin
        if (cos_phase[EFFECTIVE_LUT_WIDTH])
            cos_lut_index <= !reset_n ? 0 : ~cos_phase[EFFECTIVE_LUT_WIDTH - 1 : 0];
        else
            cos_lut_index <= !reset_n ? 0 : cos_phase[EFFECTIVE_LUT_WIDTH - 1 : 0];
    end
end

// lut reading, stage 3
reg in_valid_buf3;
reg signed [OUT_DW-1:0] sin_lut_data, cos_lut_data;
reg unsigned [1:0] sin_quadrant_index2, cos_quadrant_index2;
always_ff @(posedge clk) begin
    in_valid_buf3 <= !reset_n ? 0 : in_valid_buf2;
    sin_quadrant_index2 <= !reset_n ? 0 : sin_quadrant_index;
    sin_lut_data <= !reset_n ? 0 : lut[sin_lut_index];
    if (SIN_COS) begin
        cos_quadrant_index2 <= !reset_n ? 0 : cos_quadrant_index;
        cos_lut_data <= !reset_n ? 0 : lut[cos_lut_index];
    end
    if(in_valid_buf2) begin
        $display("lut[%d] = %d",sin_lut_index, lut[sin_lut_index]);
        $display("lut[%d] = %d",cos_lut_index, lut[cos_lut_index]);
    end
end

// output buffer, stage 4
reg unsigned [OUT_DW - 1 : 0] out_sin_buf;
reg unsigned [OUT_DW - 1 : 0] out_cos_buf;
reg out_valid_buf;
always_ff @(posedge clk) begin
    if (sin_quadrant_index2[1])
        out_sin_buf <= !reset_n ? 0 : -sin_lut_data;
    else
        out_sin_buf <= !reset_n ? 0 : sin_lut_data;
    if (SIN_COS) begin
        if (cos_quadrant_index2[1])
            out_cos_buf <= !reset_n ? 0 : -cos_lut_data;
        else
            out_cos_buf <= !reset_n ? 0 : cos_lut_data;
    end
    out_valid_buf <= !reset_n ? 0 : in_valid_buf3;    
end

assign m_axis_out_sin_tdata = out_sin_buf;
assign m_axis_out_sin_tvalid = out_valid_buf;
assign m_axis_out_cos_tdata = out_cos_buf;
assign m_axis_out_cos_tvalid = out_valid_buf;

endmodule