`timescale 1ns / 1ns

module dds
/*********************************************************************************************/
#(
    parameter PHASE_DW = 16,          // phase data width
    parameter OUT_DW = 16,            // output data width
    parameter USE_TAYLOR = 1,         // use taylor approximation
    parameter LUT_DW = 10,            // width of sine lut if taylor approximation is used
    parameter SIN_COS = 0,            // set to 1 if cos output in addition to sin output is desired
    parameter NEGATIVE_SINE = 0,      // invert sine output if set to 1
    parameter NEGATIVE_COSINE = 0,    // invert cosine output of set to 1
    parameter DECIMAL_SHIFT = 0,      // not used
    parameter USE_LUT_FILE = 0
)
/*********************************************************************************************/
(
    input                                   clk,
    input                                   reset_n,
    input   wire           [PHASE_DW-1:0]   s_axis_phase_tdata,
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
reg [PHASE_DW - 1 : 0] phase_buf;
reg in_valid_buf;
always_ff @(posedge clk) begin
    phase_buf <= !reset_n ? 0 : (s_axis_phase_tvalid ? s_axis_phase_tdata : phase_buf);
    in_valid_buf <= !reset_n ? 0 : s_axis_phase_tvalid;
end

// ------------------- SIN COS LUT -----------------------------
localparam EFFECTIVE_LUT_WIDTH = USE_TAYLOR ? LUT_DW : PHASE_DW - 2;

reg signed [OUT_DW - 1 : 0] lut [0 : 2**EFFECTIVE_LUT_WIDTH - 1];
initial	begin
    if (USE_LUT_FILE) begin
        `ifdef LUT_PATH  // recommended to use this
            $display("LUT_PATH = %s",`LUT_PATH);
            $readmemh($sformatf("%s/sine_lut_%0d_%0d.hex",`LUT_PATH,EFFECTIVE_LUT_WIDTH,OUT_DW), lut);  // for makefile            
        `elsif COCOTB_SIM
            $readmemh($sformatf("sine_lut_%0d_%0d.hex",EFFECTIVE_LUT_WIDTH,OUT_DW), lut);  // for pytest, depends on execution dir
        `else // for vivado
            $readmemh($sformatf("../../../submodules/DDS/lut_data/sine_lut_%0d_%0d.hex",EFFECTIVE_LUT_WIDTH,OUT_DW), lut);
        `endif
    end else begin
        integer i;
        for (i = 0; i < 2 ** EFFECTIVE_LUT_WIDTH; i = i + 1) begin
            // implicit conversion from real to integer does round away from zero
            // explicit conversion with $rtoi() does truncation
            // https://stackoverflow.com/questions/42003998/systemverilog-round-real-type
            lut[i] = $sin(2 * 3.141592653589793238 * $itor(i) / $itor((2 ** EFFECTIVE_LUT_WIDTH)) / 4) * $itor((2** (OUT_DW - 1) - 1));
        end
    end

    if (USE_TAYLOR) begin
        if (LUT_DW > PHASE_DW - 2) begin
            $display("LUT_DW > PHASE_DW - 2 does not make sense!");
            $finish;
        end
    end
end

// calculate lut index, stage 2
reg in_valid_buf2;
reg [EFFECTIVE_LUT_WIDTH-1:0] sin_lut_index, cos_lut_index;
reg [1:0] sin_quadrant_index;
always_ff @(posedge clk) begin
    if (!reset_n) begin
        cos_lut_index <= '0;
        sin_lut_index <= '0;
        sin_quadrant_index <= '0;
        in_valid_buf2 <= '0;
    end else begin
        in_valid_buf2 <= in_valid_buf;
        sin_quadrant_index <= phase_buf[PHASE_DW-1:PHASE_DW-2];  
        // sin
        if (phase_buf[PHASE_DW - 2]) // if in 2nd or 4th quadrant
            sin_lut_index <= ~phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH] + 1;
        else
            sin_lut_index <= phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH];
        // cos
        if (SIN_COS || USE_TAYLOR) begin
            if (!phase_buf[PHASE_DW - 2]) // if in 1st or 3rd quadrant
                cos_lut_index <= ~phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH] + 1;
            else
                cos_lut_index <= phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH];
        end
    end
end

// lut reading, stage 3
reg in_valid_buf3;
reg signed [OUT_DW-1:0] sin_lut_data, cos_lut_data;
reg [1:0] sin_quadrant_index2;
always_ff @(posedge clk) begin
    if (!reset_n) begin
        in_valid_buf3 <= '0;
        sin_lut_data <= '0;
        cos_lut_data <= '0;
        sin_quadrant_index2 <= '0;
    end else begin
        in_valid_buf3 <= in_valid_buf2;
        // sin
        sin_quadrant_index2 <= sin_quadrant_index;
        if (sin_quadrant_index[0] && sin_lut_index == 0)
            sin_lut_data <= 2**(OUT_DW-1) - 1;
        else
            sin_lut_data <= lut[sin_lut_index];
        // cos
        if (SIN_COS || USE_TAYLOR) begin
            if (!sin_quadrant_index[0] && cos_lut_index == 0)
                cos_lut_data <= 2**(OUT_DW-1) - 1;
            else
                cos_lut_data <= lut[cos_lut_index];
        end
    end
end

// output buffer, stage 4
reg signed [OUT_DW - 1 : 0] out_sin_buf;
reg signed [OUT_DW - 1 : 0] out_cos_buf;
reg out_valid_buf;
always_ff @(posedge clk) begin
    if (!reset_n) begin
        out_cos_buf <= '0;
        out_sin_buf <= '0;
        out_valid_buf <= '0;
    end else begin
        if (sin_quadrant_index2[1]) // if in 3rd or 4th quadrant
            out_sin_buf <= NEGATIVE_SINE ? sin_lut_data : -sin_lut_data;
        else
            out_sin_buf <= NEGATIVE_SINE ? -sin_lut_data : sin_lut_data;
        if (SIN_COS || USE_TAYLOR) begin
            if (sin_quadrant_index2 == 2'b10 || sin_quadrant_index2 == 2'b01) // if in 2nd or 3rd quadrant
                out_cos_buf <= NEGATIVE_COSINE ? cos_lut_data : -cos_lut_data ;
            else
                out_cos_buf <= NEGATIVE_COSINE ? -cos_lut_data : cos_lut_data ;
        end
        out_valid_buf <= in_valid_buf3;          
    end
end

// ------------------- TAYLOR CORRECTION -----------------------------
// TODO: add negative offset to phase error so that taylor correction is effective in 2 directions, should improve accuracy

// taylor phase offset multiplication, stage 2-5
localparam PHASE_ERROR_WIDTH = USE_TAYLOR ? PHASE_DW - (LUT_DW + 2) : 1;
localparam PHASE_FACTOR_WIDTH = 18;  // 18 is width of small operand of DSP48E1 
localparam PI_DECIMAL_SHIFT   = 14;  // this leaves 4 bits for 2*pi which is enough
localparam real PHASE_FACTOR_REAL = (2 * 3.141592654) * 2**PI_DECIMAL_SHIFT;
// typedef bit [PHASE_FACTOR_WIDTH - 1 : 0] t_PHASE_FACTOR;
localparam [PHASE_FACTOR_WIDTH - 1 : 0] PHASE_FACTOR = $rtoi(PHASE_FACTOR_REAL);

localparam SIN_COS_LUT_BALANCING_STAGES = 2;  // this value has to be 2, otherwise valid will be out of sync
reg [PHASE_ERROR_WIDTH - 1 : 0]    phase_error_buf [0 : SIN_COS_LUT_BALANCING_STAGES - 1];
localparam EXTENDED_WIDTH    = PHASE_FACTOR_WIDTH + PHASE_ERROR_WIDTH;

reg signed   [EXTENDED_WIDTH - 1 : 0]    phase_error_multiplied_extended;  // for M reg of DSP
reg signed   [EXTENDED_WIDTH - 1 : 0]    phase_error_multiplied_extended_buf; // for P reg of DSP
reg signed [OUT_DW-1 : 0] out_sin_phase;
reg signed [OUT_DW-1 : 0] out_cos_phase;
reg phase_error_valid;
integer i;
if (USE_TAYLOR) begin
    always_ff@(posedge clk) begin
        if (!reset_n) begin
            phase_error_valid <= '0;
            for(i = 0; i < SIN_COS_LUT_BALANCING_STAGES; i = i + 1) begin
                phase_error_buf[i] <= '0;
            end
            out_sin_phase <= '0;
            out_cos_phase <= '0;
        end else begin
            for(i = 0; i < SIN_COS_LUT_BALANCING_STAGES; i = i + 1) begin
                if(i == 0)
                    phase_error_buf[0] <= phase_buf[PHASE_ERROR_WIDTH - 1: 0];
                else
                    phase_error_buf[i] <= phase_error_buf[i - 1];
            end
            phase_error_multiplied_extended <= phase_error_buf[SIN_COS_LUT_BALANCING_STAGES-1] * PHASE_FACTOR; 
            phase_error_multiplied_extended_buf <= phase_error_multiplied_extended;
            phase_error_valid <= out_valid_buf;
            out_sin_phase <= out_sin_buf;
            out_cos_phase <= out_cos_buf;
        end
    end
end
wire signed  [EXTENDED_WIDTH - PI_DECIMAL_SHIFT - 1 : 0]    phase_error_multiplied;
assign phase_error_multiplied = phase_error_multiplied_extended_buf[EXTENDED_WIDTH - 1 : 14];

// taylor correction pipeline, stage 6-8
localparam TAYLOR_PIPELINE_STAGES = 3;    // 2 for input of taylor mult, 1 for mult, so 3 should be enough
reg signed [OUT_DW - 1 : 0] out_sin_buf_taylor[TAYLOR_PIPELINE_STAGES - 2 : 0];
reg signed [OUT_DW - 1 : 0] out_cos_buf_taylor[TAYLOR_PIPELINE_STAGES - 2 : 0];
reg signed [EXTENDED_WIDTH - PI_DECIMAL_SHIFT - 1 : 0] phase_error_multiplied_buf[TAYLOR_PIPELINE_STAGES - 2 : 0];
// duplicate reg so that it can be pulled into dsp
// vivado 2020.2 is not smart enough to do it
reg signed [EXTENDED_WIDTH - PI_DECIMAL_SHIFT - 1 : 0] phase_error_multiplied_buf2[TAYLOR_PIPELINE_STAGES - 2 : 0];  
reg signed [TAYLOR_MULT_WIDTH - 1 : 0] sin_times_phase;
reg signed [TAYLOR_MULT_WIDTH - 1 : 0] cos_times_phase;
reg signed [TAYLOR_MULT_WIDTH - 1 : 0] sin_extended[TAYLOR_PIPELINE_STAGES - 1 : 0];
reg signed [TAYLOR_MULT_WIDTH - 1 : 0] cos_extended[TAYLOR_PIPELINE_STAGES - 1 : 0];
reg [TAYLOR_PIPELINE_STAGES - 1 : 0] valid_taylor;
if (USE_TAYLOR) begin
    always_ff@(posedge clk) begin
        integer k;
        for (k = 0; k < TAYLOR_PIPELINE_STAGES; k = k + 1) begin
            if (!reset_n) begin
                out_sin_buf_taylor[k] <= '0;
                out_cos_buf_taylor[k] <= '0;
                sin_extended[k] <= '0;
                cos_extended[k] <= '0;
                phase_error_multiplied_buf[k] <= '0;
                phase_error_multiplied_buf2[k] <= '0;
                valid_taylor[k] <= '0;
            end else begin
                if(k == 0) begin  // stage 5
                    out_sin_buf_taylor[k]           <= out_sin_phase;
                    out_cos_buf_taylor[k]           <= out_cos_phase;
                    sin_extended[k]                 <= {out_sin_phase, {(TAYLOR_MULT_WIDTH - OUT_DW){1'b0}}};  // multiply by 2**(PHASE_DW)
                    cos_extended[k]                 <= {out_cos_phase, {(TAYLOR_MULT_WIDTH - OUT_DW){1'b0}}};  // multiply by 2**(PHASE_DW)
                    phase_error_multiplied_buf[k]   <= phase_error_multiplied;
                    phase_error_multiplied_buf2[k]  <= phase_error_multiplied;
                    valid_taylor[k]                 <= phase_error_valid;
                end
                else if (k < TAYLOR_PIPELINE_STAGES -1) begin  // stages 6-7
                    out_sin_buf_taylor[k]           <= out_sin_buf_taylor[k-1];
                    out_cos_buf_taylor[k]           <= out_cos_buf_taylor[k-1];
                    sin_extended[k]                 <= sin_extended[k-1];
                    cos_extended[k]                 <= cos_extended[k-1];
                    phase_error_multiplied_buf[k]   <= phase_error_multiplied_buf[k-1];
                    phase_error_multiplied_buf2[k]  <= phase_error_multiplied_buf2[k-1];
                    valid_taylor[k]                 <= valid_taylor[k-1];
                end
                else begin  // stage 8: multiplication and further pipelien add operands
                    sin_times_phase <= out_sin_buf_taylor[k-1] * phase_error_multiplied_buf[k-1];
                    cos_times_phase <= out_cos_buf_taylor[k-1] * phase_error_multiplied_buf2[k-1];
                    sin_extended[k] <= sin_extended[k-1];
                    cos_extended[k] <= cos_extended[k-1];
                    valid_taylor[k] <= valid_taylor[k-1];
                end
            end
        end        
    end
end

localparam TAYLOR_MULT_WIDTH = PHASE_DW + OUT_DW;
// TAYLOR_MULT_WIDTH should fit into the large add operand of a DSP48E1 which is 48 bits
wire signed [TAYLOR_MULT_WIDTH - 1 : 0] sin_corrected, cos_corrected;  // cannot truncate unneeded bits here, because vivado wont pull register into dsp then

if (NEGATIVE_SINE != NEGATIVE_COSINE) begin
    assign sin_corrected = sin_extended[TAYLOR_PIPELINE_STAGES - 1] - cos_times_phase;
    assign cos_corrected = cos_extended[TAYLOR_PIPELINE_STAGES - 1] + sin_times_phase;
end
else begin
    assign sin_corrected = sin_extended[TAYLOR_PIPELINE_STAGES - 1] + cos_times_phase;
    assign cos_corrected = cos_extended[TAYLOR_PIPELINE_STAGES - 1] - sin_times_phase;
end

// taylor correction, stage 9 : addition and output buffer
localparam TAYLOR_OUT_PIPELINE_STAGES = 1;  // more than 1 does not seem to help here, dsp only pulls in 1 reg
reg signed [TAYLOR_MULT_WIDTH - 1 : 0] out_sin_buf2[TAYLOR_OUT_PIPELINE_STAGES - 1 : 0];
reg signed [TAYLOR_MULT_WIDTH - 1 : 0] out_cos_buf2[TAYLOR_OUT_PIPELINE_STAGES - 1 : 0];
reg out_valid_buf2[TAYLOR_OUT_PIPELINE_STAGES - 1 : 0];
if (USE_TAYLOR) begin
    always_ff @(posedge clk) begin
        integer k;
        for (k = 0; k < TAYLOR_OUT_PIPELINE_STAGES; k = k + 1) begin
            if (k == 0) begin  // addition
                out_sin_buf2[0]     <= !reset_n ? 0 : sin_corrected;
                out_cos_buf2[0]     <= !reset_n ? 0 : cos_corrected; 
                out_valid_buf2[0]   <= !reset_n ? 0 : valid_taylor[TAYLOR_PIPELINE_STAGES-1];    
            end
            else begin  // pipeline result of addition
                out_sin_buf2[k]     <= !reset_n ? 0 : out_sin_buf2[k-1];
                out_cos_buf2[k]     <= !reset_n ? 0 : out_cos_buf2[k-1];
                out_valid_buf2[k]   <= !reset_n ? 0 : out_valid_buf2[k-1];
            end
        end
    end
end

if (USE_TAYLOR) begin
    wire signed [TAYLOR_MULT_WIDTH -1 : 0] out_sin;  // create wires to truncate unneeded bits (divide by 2**(PHASE_DW))
    wire signed [TAYLOR_MULT_WIDTH -1 : 0] out_cos;
    assign out_sin = out_sin_buf2[TAYLOR_OUT_PIPELINE_STAGES - 1];
    assign out_cos = out_cos_buf2[TAYLOR_OUT_PIPELINE_STAGES - 1];
    assign m_axis_out_sin_tdata = out_sin[TAYLOR_MULT_WIDTH - 1 -: OUT_DW];
    assign m_axis_out_cos_tdata = out_cos[TAYLOR_MULT_WIDTH - 1 -: OUT_DW];
    assign m_axis_out_sin_tvalid = out_valid_buf2[TAYLOR_OUT_PIPELINE_STAGES - 1];
    assign m_axis_out_cos_tvalid = out_valid_buf2[TAYLOR_OUT_PIPELINE_STAGES - 1];    
end
else begin
    assign m_axis_out_sin_tdata = out_sin_buf;
    assign m_axis_out_cos_tdata = out_cos_buf;
    assign m_axis_out_sin_tvalid = out_valid_buf;
    assign m_axis_out_cos_tvalid = out_valid_buf;
end
assign m_axis_out_tdata = {m_axis_out_sin_tdata, m_axis_out_cos_tdata};
assign m_axis_out_tvalid = m_axis_out_sin_tvalid;

endmodule