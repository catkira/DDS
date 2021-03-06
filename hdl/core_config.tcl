set display_name {DDS}

set core [ipx::current_core]

set_property DISPLAY_NAME $display_name $core
set_property DESCRIPTION $display_name $core

core_parameter PHASE_DW {PHASE WIDTH} {Width of the phase operands}
core_parameter OUT_DW {OPERAND WIDTH OUTPUT} {Width of the output operands}
core_parameter USE_TAYLOR {USE TAYLOR SERIES APPORXIMATION} {Use taylor series approximation of set to 1}
core_parameter LUT_DW  {LUT WIDTH} {LUT width of taylor series approximation is used}
core_parameter SIN_COS  {SIN COS} {Additional cos output if 1}
core_parameter DECIMAL_SHIFT  {DECIMAL SHIFT} {Used for scaling the taylor approximation factor}

set bus [ipx::get_bus_interfaces -of_objects $core s_axis_phase]
set_property NAME S_AXIS_PHASE $bus
set_property INTERFACE_MODE slave $bus

set bus [ipx::get_bus_interfaces -of_objects $core m_axis_out_sin]
set_property NAME M_AXIS_OUT_SIN $bus
set_property INTERFACE_MODE master $bus

set bus [ipx::get_bus_interfaces -of_objects $core m_axis_out_cos]
set_property NAME M_AXIS_OUT_COS $bus
set_property INTERFACE_MODE master $bus

set bus [ipx::get_bus_interfaces -of_objects $core m_axis_out]
set_property NAME M_AXIS_OUT $bus
set_property INTERFACE_MODE master $bus

set bus [ipx::get_bus_interfaces clk]
set parameter [ipx::get_bus_parameters -of_objects $bus ASSOCIATED_BUSIF]
set_property VALUE S_AXIS_PHASE:M_AXIS_OUT_SIN:M_AXIS_OUT_COS:M_AXIS_OUT $parameter
