# DDS

This is a DDS core written in system verilog. It uses a quarter-wave lut plus optional taylor series approximation.

To run the unit tests install
- python >3.8
- iverilog >1.4
- python modules: cocotb, cocotb_test, pytest, pytest-parallel

and run pytest in the repo directory
```
pytest -v --workers 10
```

# TODO
- tests on hardware

# References
- http://www.martin-kumm.de/wiki/doku.php?id=04FPGA_Cores:DDS_Synthesizer
- https://zipcpu.com/dsp/2017/08/26/quarterwave.html
- https://github.com/spr02/DDS

# License

GPL