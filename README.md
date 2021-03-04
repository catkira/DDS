# DDS

This project uses code and ideas from https://zipcpu.com/dsp/2017/08/26/quarterwave.html by Gisselquist Technology and http://www.martin-kumm.de/wiki/doku.php?id=04FPGA_Cores:DDS_Synthesizer by Martin Kumm

The main additions and changes are
- python model for simulation
- unit tests using cocotb and cocotb-test

To run the unit tests install
- python >3.8
- iverilog >1.4
- python modules: cocotb, cocotb_test, pytest, pytest-parallel

and run pytest in the repo directory
```
pytest -v --workers 10
```

# License

for new code GPL, for old code see original license