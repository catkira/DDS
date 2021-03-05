`timescale 1ns / 1ns

module dds
/*********************************************************************************************/
#(
    parameter PHASE_DW = 16,          // phase data width
    parameter OUT_DW = 16,            // output data width
    parameter USE_TAYLOR = 0,         // use taylor approximation
    parameter LUT_WIDTH = 10          // width of sine lut if taylor approximation is used
)
/*********************************************************************************************/
(
    input                                   clk,
    input                                   reset_n,
    input   wire  unsigned [PHASE_DW-1:0]   s_axis_phase_tdata,
    input                                   s_axis_phase_tvalid,
    output  wire    signed [OUT_DW-1:0]     m_axis_out_tdata,
    output                                  m_axis_out_tvalid 
);
/*********************************************************************************************/

localparam EFFECTIVE_LUT_WIDTH = USE_TAYLOR ? LUT_WIDTH : PHASE_DW - 2;

reg signed [OUT_DW - 1 : 0] lut [0 : 2**EFFECTIVE_LUT_WIDTH - 1];
initial begin
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
reg unsigned [EFFECTIVE_LUT_WIDTH-1:0] lut_index;
reg unsigned [1:0] quadrant_index;
always_ff @(posedge clk) begin
    in_valid_buf2 <= !reset_n ? 0 : in_valid_buf;
    quadrant_index <= !reset_n ? 0 : phase_buf[EFFECTIVE_LUT_WIDTH+1:EFFECTIVE_LUT_WIDTH];
    if (phase_buf[EFFECTIVE_LUT_WIDTH])
        lut_index <= !reset_n ? 0 : ~phase_buf[EFFECTIVE_LUT_WIDTH - 1 : 0];
    else
        lut_index <= !reset_n ? 0 : ~phase_buf[EFFECTIVE_LUT_WIDTH - 1 : 0];
end

// lut reading, stage 3
reg in_valid_buf3;
reg signed [OUT_DW-1:0] lut_data;
reg unsigned [1:0] quadrant_index2;
always_ff @(posedge clk) begin
    in_valid_buf3 <= !reset_n ? 0 : in_valid_buf2;
    quadrant_index2 <= !reset_n ? 0 : quadrant_index;
    lut_data <= !reset_n ? 0 : lut[lut_index];
end

// output buffer, stage 4
reg unsigned [OUT_DW - 1 : 0] out_buf;
reg out_valid_buf;
always_ff @(posedge clk) begin
    if (quadrant_index2[1])
        out_buf <= !reset_n ? 0 : -lut_data;
    else
        out_buf <= !reset_n ? 0 : lut_data;
    out_valid_buf <= !reset_n ? 0 : in_valid_buf3;    
end

assign m_axis_out_tdata = out_buf;
assign m_axis_out_tvalid = out_valid_buf;

endmodule