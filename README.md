[![Verify](https://github.com/catkira/DDS/actions/workflows/verify.yml/badge.svg)](https://github.com/catkira/DDS/actions/workflows/verify.yml)

# Direct Digital Synthesizer
## Overview

This is a DDS core written in system verilog. It uses a quarter-wave lut plus optional taylor series approximation. The code is optimized and tested for XILINX Series 7 FPGAs with Vivado 2020.2 but should also work on other products. In that case some register widths might be not optimal, most register widths are currently optimized to fit in a DSP48E1 unit.

The sin-cos lut uses a lookup table that needs to be precalculated using tools/generate_sine_lut.py script. The generated hex file needs to be placed in a location where the $readmemh command can find it. This might vary depending on the synthesizer used.

## PARAMETERS
- PHASE_DW selects the number of bits for the phase input
- OUT_DW selects the number of bits for the output
- USE_TAYLOR enables taylor series correction if set to 1
- LUT_DW not used if USE_TAYLOR = 0. In this case LUT_DW is set to PHASE_DW - 2 so that the entire waveform is created by the lut. If USE_TAYLOR = 1, this value can be used to set the degree of interpolation by taylor series correction.
- SIN_COS output additional cosine if set to one
- NEGATIVE_SINE inverts sine output if set to 1
- NEGATIVE_COSINE inverts cosine output if set to 1

## PORTS
- CLK clock
- reset_n active low reset
- s_axis_phase AXI Stream interface for phase input
- m_axis_out AXI Stream interface for combined sin and cos output, width is 2*OUT_DW
- m_axis_out_sin AXI Stream interface for sin output
- m_axis_out_cos AXI Stream interface for cos output

## Verification
To run the unit tests install
- python >3.8
- iverilog >1.4
- python modules: cocotb, cocotb_test, pytest, pytest-parallel, pytest-cov

and run pytest in the repo directory
```
pytest -v --workers 10
```

## TODO
- add taylor series correction in negative direction, should improve accuracy slightly
- put sin-cos lut in separate module
- benchmark error against Xilinx DDS

## References
- http://www.martin-kumm.de/wiki/doku.php?id=04FPGA_Cores:DDS_Synthesizer
- https://zipcpu.com/dsp/2017/08/26/quarterwave.html
- https://github.com/spr02/DDS
- https://www.fpga4fun.com/DDS2.html

## License
GPL
