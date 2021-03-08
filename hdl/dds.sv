`timescale 1ns / 1ns

module dds
/*********************************************************************************************/
#(
    parameter PHASE_DW = 16,          // phase data width
    parameter OUT_DW = 16,            // output data width
    parameter USE_TAYLOR = 0,         // use taylor approximation
    parameter LUT_DW = 10,            // width of sine lut if taylor approximation is used
    parameter SIN_COS = 0,            // set to 1 if cos output in addition to sin output is desired
    parameter DECIMAL_SHIFT = 0       // not used
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
    output                                  m_axis_out_cos_tvalid,
    output  wire    signed [2*OUT_DW-1:0]   m_axis_out_tdata,
    output                                  m_axis_out_tvalid
);
/*********************************************************************************************/
// input buffer, stage 1
reg unsigned [PHASE_DW - 1 : 0] phase_buf;
reg in_valid_buf;
always_ff @(posedge clk) begin
    phase_buf <= !reset_n ? 0 : (s_axis_phase_tvalid ? s_axis_phase_tdata : phase_buf);
    in_valid_buf <= !reset_n ? 0 : s_axis_phase_tvalid;
end

// ------------------- SIN COS LUT -----------------------------
//  TODO: put sin-cos lut in separate module
localparam EFFECTIVE_LUT_WIDTH = USE_TAYLOR ? LUT_DW : PHASE_DW - 2;

reg signed [OUT_DW - 1 : 0] lut [0 : 2**EFFECTIVE_LUT_WIDTH - 1];
// `include "sine_lut_10_16.vh"  // I dont know how to insert variable numbers into the include string
initial	begin
    `ifdef COCOTB_SIM
        $readmemh($sformatf("../../hdl/sine_lut_%0d_%0d.hex",EFFECTIVE_LUT_WIDTH,OUT_DW), lut);
    `else
        $readmemh($sformatf("../../../submodules/DDS/lut_data/sine_lut_%0d_%0d.hex",EFFECTIVE_LUT_WIDTH,OUT_DW), lut);
    `endif
    if (USE_TAYLOR) begin
        if (LUT_DW > PHASE_DW - 2) begin
            $display("LUT_DW > PHASE_DW - 2 does not make sense!");
            $finish;
        end
    end
end

// calculate lut index, stage 2
reg in_valid_buf2;
reg unsigned [EFFECTIVE_LUT_WIDTH-1:0] sin_lut_index, cos_lut_index;
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
end

// lut reading, stage 3
reg in_valid_buf3;
reg signed [OUT_DW-1:0] sin_lut_data, cos_lut_data;
reg unsigned [1:0] sin_quadrant_index2;
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
    // debug stuff
    if(in_valid_buf2) begin
        // $display("lut[%d] = %d",sin_lut_index, sin_lut_data);
        // $display("lut[%d] = %d",cos_lut_index, cos_lut_data);
    end
end

// output buffer, stage 4
reg signed [OUT_DW - 1 : 0] out_sin_buf;
reg signed [OUT_DW - 1 : 0] out_cos_buf;
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
    out_valid_buf <= !reset_n ? 0 : in_valid_buf3;    
end

// ------------------- TAYLOR CORRECTION -----------------------------
// TODO: add negative offset to phase error so that taylor correction is effective in 2 directions, should improve accuracy

// taylor phase offset multiplication, stage 2-3
localparam PHASE_ERROR_WIDTH = USE_TAYLOR ? PHASE_DW - (LUT_DW + 2) : 1;
localparam PHASE_FACTOR_WIDTH = 18;  // 18 is width of small operand of DSP48E1 
localparam PI_DECIMAL_SHIFT   = 14;  // this leaves 4 bits for 2*pi which is enough
localparam real PHASE_FACTOR_REAL = (2 * 3.141592654) * 2**PI_DECIMAL_SHIFT;
typedef bit unsigned [PHASE_FACTOR_WIDTH - 1 : 0] t_PHASE_FACTOR;
localparam t_PHASE_FACTOR PHASE_FACTOR = t_PHASE_FACTOR'(PHASE_FACTOR_REAL);

localparam SIN_LUT_DELAY = 1;
reg unsigned [PHASE_ERROR_WIDTH - 1 : 0]    phase_error_buf [0:SIN_LUT_DELAY];
localparam EXTENDED_WIDTH    = PHASE_FACTOR_WIDTH + PHASE_ERROR_WIDTH;

reg signed   [EXTENDED_WIDTH - 1 : 0]       phase_error_multiplied_extended;
if (USE_TAYLOR) begin
    always_ff@(posedge clk) begin
        foreach(phase_error_buf[k]) begin
            if(k == 0)
                phase_error_buf[0] <= !reset_n ? 0 : phase_buf[PHASE_ERROR_WIDTH - 1: 0];
            else
                phase_error_buf[k] <= !reset_n ? 0 : phase_error_buf[k-1];
        end
        phase_error_multiplied_extended <= !reset_n ? 0 : phase_error_buf[SIN_LUT_DELAY] * PHASE_FACTOR; 
    end
end
wire signed  [EXTENDED_WIDTH - PI_DECIMAL_SHIFT - 1 : 0]    phase_error_multiplied;
assign phase_error_multiplied = phase_error_multiplied_extended[EXTENDED_WIDTH - 1 : 14];

// taylor correction pipeline, stage 4-6
localparam TAYLOR_PIPELINE_STAGES = 2;
reg signed [OUT_DW - 1 : 0] out_sin_buf_taylor[TAYLOR_PIPELINE_STAGES - 1 : 0];
reg signed [OUT_DW - 1 : 0] out_cos_buf_taylor[TAYLOR_PIPELINE_STAGES - 1 : 0];
reg signed [EXTENDED_WIDTH - PI_DECIMAL_SHIFT - 1 : 0] phase_error_multiplied_buf[TAYLOR_PIPELINE_STAGES - 1 : 0];
reg [TAYLOR_PIPELINE_STAGES - 1 : 0] valid_taylor;
if (USE_TAYLOR) begin
    always_ff@(posedge clk) begin
        foreach(out_sin_buf_taylor[k]) begin
            if(k == 0) begin
                out_sin_buf_taylor[k] <= !reset_n ? 0 : out_sin_buf;
                out_cos_buf_taylor[k] <= !reset_n ? 0 : out_cos_buf;
                phase_error_multiplied_buf[k] <= !reset_n ? 0 : phase_error_multiplied;
                valid_taylor[k] <= !reset_n ? 0 : out_valid_buf;
            end
            else begin
                out_sin_buf_taylor[k] <= !reset_n ? 0 : out_sin_buf_taylor[k-1];
                out_cos_buf_taylor[k] <= !reset_n ? 0 : out_cos_buf_taylor[k-1];
                phase_error_multiplied_buf[k] <= !reset_n ? 0 : phase_error_multiplied_buf[k-1];
                valid_taylor[k] <= !reset_n ? 0 : valid_taylor[k-1];
            end
        end        
    end
end

// taylor correction, stage 7
localparam TAYLOR_MULT_WIDTH = PHASE_DW + OUT_DW;
// TAYLOR_MULT_WIDTH should fit into the large add operand of a DSP48E1 which is 48 bits
wire signed [TAYLOR_MULT_WIDTH - 1 : 0] sin_extended, cos_extended;
wire signed [TAYLOR_MULT_WIDTH - 1 : 0] sin_corrected, cos_corrected;

assign sin_extended = {out_sin_buf_taylor[TAYLOR_PIPELINE_STAGES - 1], {(TAYLOR_MULT_WIDTH - OUT_DW){1'b0}}};  // multiply by 2**(PHASE_DW)
assign sin_corrected = sin_extended + out_cos_buf_taylor[TAYLOR_PIPELINE_STAGES - 1] * phase_error_multiplied_buf[TAYLOR_PIPELINE_STAGES - 1];
assign cos_extended = {out_cos_buf_taylor[TAYLOR_PIPELINE_STAGES - 1], {(TAYLOR_MULT_WIDTH - OUT_DW){1'b0}}};  // multiply by 2**(PHASE_DW)
assign cos_corrected = cos_extended - out_sin_buf_taylor[TAYLOR_PIPELINE_STAGES - 1] * phase_error_multiplied_buf[TAYLOR_PIPELINE_STAGES - 1];

reg signed [OUT_DW - 1 : 0] out_sin_buf2;
reg signed [OUT_DW - 1 : 0] out_cos_buf2;
reg out_valid_buf2;
if (USE_TAYLOR) begin
    always_ff @(posedge clk) begin
        // if (out_valid_buf && USE_TAYLOR) begin
        //     if(out_cos_buf < 0)
        //         $display("out_cos_buf = %d, factor = %d", out_cos_buf, TAYLOR_MULT_WIDTH'(out_cos_buf * phase_error_multiplied));
        // end
        out_sin_buf2 <= !reset_n ? 0 : sin_corrected[TAYLOR_MULT_WIDTH - 1 -: OUT_DW];  // divide by 2**(PHASE_DW)
        out_cos_buf2 <= !reset_n ? 0 : cos_corrected[TAYLOR_MULT_WIDTH - 1 -: OUT_DW];  // divide by 2**(PHASE_DW)
        out_valid_buf2 <= !reset_n ? 0 : valid_taylor[TAYLOR_PIPELINE_STAGES-1];    
    end
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
assign m_axis_out_tdata = {m_axis_out_sin_tdata, m_axis_out_cos_tdata};
assign m_axis_out_tvalid = m_axis_out_sin_tvalid;

endmodule