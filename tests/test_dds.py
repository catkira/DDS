import random
import os
import logging
import pytest
import numpy as np
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer
from cocotb.triggers import RisingEdge
import cocotb_test.simulator

import importlib.util

CLK_PERIOD_NS = 2
CLK_PERIOD_S = CLK_PERIOD_NS * 0.000000001

class TB(object):
    def __init__(self,dut):
        random.seed(30) # reproducible tests
        self.dut = dut
        self.PHASE_DW = int(dut.PHASE_DW)
        self.OUT_DW = int(dut.OUT_DW)
        self.USE_TAYLOR = int(dut.USE_TAYLOR)
        self.LUT_DW = int(dut.LUT_DW)
        self.SIN_COS = int(dut.SIN_COS)
        self.NEGATIVE_SINE = int(dut.NEGATIVE_SINE)
        self.NEGATIVE_COSINE = int(dut.NEGATIVE_COSINE)
        self.USE_LUT_FILE = int(dut.USE_LUT_FILE)

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.input = []
        # using a higher than 1 frequency here speeds up simulation,
        # because the simulation runs until a half-wave is done for each phase width.
        # However not every LUT entry will get tested if frequency > 1
        self.freq = 100

        tests_dir = os.path.abspath(os.path.dirname(__file__))
        model_dir = os.path.abspath(os.path.join(tests_dir, '../model/dds_model.py'))
        spec = importlib.util.spec_from_file_location("dds_model", model_dir)
        foo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(foo)
        self.model = foo.Model(self.PHASE_DW, self.OUT_DW, self.USE_TAYLOR, self.LUT_DW, self.SIN_COS, self.NEGATIVE_SINE, self.NEGATIVE_COSINE) 
        cocotb.start_soon(Clock(self.dut.clk, CLK_PERIOD_NS, units='ns').start())
        cocotb.start_soon(self.model_clk(CLK_PERIOD_NS, 'ns'))
          
    async def model_clk(self, period, period_units):
        timer = Timer(period, period_units)
        while True:
            self.model.tick()
            await timer

    async def generate_input(self):
        phase = 0
        self.input = []
        while True:
            if phase >= 2**self.PHASE_DW:
                phase = (2**self.PHASE_DW-1) % phase # do wrap around
            await RisingEdge(self.dut.clk)
            self.model.set_data(phase)
            self.input.append(phase)
            self.dut.s_axis_phase_tdata.value = phase
            self.dut.s_axis_phase_tvalid.value = 1
            phase += self.freq

    async def cycle_reset(self):
        self.dut.s_axis_phase_tvalid.value = 0
        self.dut.reset_n.value = 0
        await RisingEdge(self.dut.clk)
        self.dut.reset_n.value = 0
        await RisingEdge(self.dut.clk)
        self.dut.reset_n.value = 1
        await RisingEdge(self.dut.clk)
        self.model.reset()

@cocotb.test()
async def simple_test(dut):
    tb = TB(dut)
    await tb.cycle_reset()
    #num_items = 2**int(dut.PHASE_DW)//tb.freq  # one complete wave
    num_items = 2**int(dut.PHASE_DW)//tb.freq//2  # one half wave
    #num_items = 100
    gen = cocotb.fork(tb.generate_input())
    output = []
    output_model = []
    output_cos = []
    output_model_cos = []
    count = 0
    tolerance = 0
    if tb.USE_TAYLOR:
        tolerance = 10
    print(F"tolerance = {tolerance}")
    while len(output_model) < num_items or len(output) < num_items:
        await RisingEdge(dut.clk)
        if(tb.model.data_valid()):
            output_model.append(int(tb.model.get_data()))
            output_model_cos.append(int(tb.model.get_data_cos()))
            #print(f"model:\t[{len(output_model)-1}]\t {output_model[-1]} \t {output_model_cos[-1]}")

        if dut.m_axis_out_sin_tvalid.value == 1:
            a = dut.m_axis_out_sin_tdata.value.integer
            if (a & (1 << (tb.OUT_DW - 1))) != 0:
                a = a - (1 << tb.OUT_DW)
            output.append(int(a))
            if tb.SIN_COS:
                a = dut.m_axis_out_cos_tdata.value.integer
                if (a & (1 << (tb.OUT_DW - 1))) != 0:
                    a = a - (1 << tb.OUT_DW)
            else:
                a = 0
            output_cos.append(int(a))
            #print(f"hdl: \t[{len(output)-1}]\t {output[-1]} \t {output_cos[-1]} ")
        #print(f"{int(tb.model.data_valid())} {dut.m_axis_out_tvalid}")
        count += 1
    if False:
        with open('../../out.txt', 'w') as outfile:
            np.savetxt(outfile, output, fmt='%d')
        with open('../../out_cos.txt', 'w') as outfile:
            np.savetxt(outfile, output_cos, fmt='%d')
        with open('../../out_model.txt', 'w') as outfile:
            np.savetxt(outfile, output_model, fmt='%d')
        with open('../../out_model_cos.txt', 'w') as outfile:
            np.savetxt(outfile, output_model_cos, fmt='%d')
    for i in range(num_items):
        assert np.abs(output[i] - output_model[i]) <= tolerance, f"[{i}] hdl: {output[i]} \t model: {output_model[i]}"
        if tb.SIN_COS:
            assert np.abs(output_cos[i] - output_model_cos[i]) <= tolerance, f"[{i}] hdl: {output_cos[i]} \t model: {output_model_cos[i]}"
    #print(f"received {len(output)} samples")
    gen.kill()
    tb.dut.s_axis_phase_tvalid.value = 0
# cocotb-test


tests_dir = os.path.abspath(os.path.dirname(__file__))
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', 'hdl'))
tools_dir = os.path.abspath(os.path.join(tests_dir, '..', 'tools'))

@pytest.mark.parametrize("PHASE_DW", [20, 24])
@pytest.mark.parametrize("OUT_DW", [16])
@pytest.mark.parametrize("USE_TAYLOR", [1])
@pytest.mark.parametrize("LUT_DW", [9, 11])
@pytest.mark.parametrize("SIN_COS", [1])
@pytest.mark.parametrize("NEGATIVE_SINE", [0, 1])
@pytest.mark.parametrize("NEGATIVE_COSINE", [0, 1])
@pytest.mark.parametrize("USE_LUT_FILE", [0, 1])
def test_dds_taylor(PHASE_DW, OUT_DW, USE_TAYLOR, LUT_DW, SIN_COS, NEGATIVE_SINE, NEGATIVE_COSINE, USE_LUT_FILE):
    dut = "dds"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.sv"),
    ]
    includes = [
        os.path.join(rtl_dir, ""),
    ]

    parameters = {}

    parameters['PHASE_DW'] = PHASE_DW
    parameters['OUT_DW'] = OUT_DW
    parameters['USE_TAYLOR'] = USE_TAYLOR
    parameters['LUT_DW'] = LUT_DW
    parameters['SIN_COS'] = SIN_COS
    parameters['NEGATIVE_SINE'] = NEGATIVE_SINE
    parameters['NEGATIVE_COSINE'] = NEGATIVE_COSINE
    parameters['USE_LUT_FILE'] = USE_LUT_FILE

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}
    sim_build="sim_build/dds_taylor_" + "_".join(("{}={}".format(*i) for i in parameters.items()))
    Path(sim_build).mkdir(parents=True, exist_ok=True)

    if USE_LUT_FILE:
        file_path = os.path.abspath(os.path.join(tests_dir, '../tools/generate_sine_lut.py'))
        spec = importlib.util.spec_from_file_location("generate_sine_lut", file_path)
        generate_sine_lut = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generate_sine_lut)
        lut_width = PHASE_DW -2
        if USE_TAYLOR:
            lut_width = LUT_DW
        lut_filename = os.path.abspath(os.path.join(sim_build, 'sine_lut_'+str(lut_width)+'_'+str(OUT_DW)))
        generate_sine_lut.main(['--PHASE_DW',str(lut_width),'--OUT_DW',str(OUT_DW),'--filename',lut_filename])

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        includes=includes,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
        testcase="simple_test",
    )


@pytest.mark.parametrize("PHASE_DW", [16, 8])
@pytest.mark.parametrize("OUT_DW", [16, 3])
@pytest.mark.parametrize("USE_TAYLOR", [0])
@pytest.mark.parametrize("LUT_DW", [6])
@pytest.mark.parametrize("SIN_COS", [1, 0])
@pytest.mark.parametrize("NEGATIVE_SINE", [1, 0])
@pytest.mark.parametrize("NEGATIVE_COSINE", [1, 0])
@pytest.mark.parametrize("USE_LUT_FILE", [1, 0])
def test_dds(PHASE_DW, OUT_DW, USE_TAYLOR, LUT_DW, SIN_COS, NEGATIVE_SINE, NEGATIVE_COSINE, USE_LUT_FILE):
    dut = "dds"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.sv"),
    ]
    includes = [
        os.path.join(rtl_dir, ""),
    ]

    parameters = {}
    parameters['PHASE_DW'] = PHASE_DW
    parameters['OUT_DW'] = OUT_DW
    parameters['USE_TAYLOR'] = USE_TAYLOR
    parameters['LUT_DW'] = LUT_DW
    parameters['SIN_COS'] = SIN_COS
    parameters['NEGATIVE_SINE'] = NEGATIVE_SINE
    parameters['NEGATIVE_COSINE'] = NEGATIVE_COSINE
    parameters['USE_LUT_FILE'] = USE_LUT_FILE

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}
    sim_build="sim_build/dds_" + "_".join(("{}={}".format(*i) for i in parameters.items()))
    Path(sim_build).mkdir(parents=True, exist_ok=True)

    if USE_LUT_FILE:
        file_path = os.path.abspath(os.path.join(tests_dir, '../tools/generate_sine_lut.py'))
        spec = importlib.util.spec_from_file_location("generate_sine_lut", file_path)
        generate_sine_lut = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generate_sine_lut)
        lut_width = PHASE_DW - 2
        if USE_TAYLOR:
            lut_width = LUT_DW
        lut_filename = os.path.abspath(os.path.join(sim_build, 'sine_lut_'+str(lut_width)+'_'+str(OUT_DW)))
        print(lut_filename)
        generate_sine_lut.main(['--PHASE_DW',str(lut_width),'--OUT_DW',str(OUT_DW),'--filename',lut_filename])

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        includes=includes,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
        testcase="simple_test",
        waves=True,
        force_compile=True
    )

if __name__ == '__main__':
    os.environ['PLOTS'] = '0'
    # os.environ['SIM'] = 'iverilog'
    test_dds(PHASE_DW = 16, OUT_DW = 3, USE_TAYLOR = 1, LUT_DW = 6, SIN_COS = 1, NEGATIVE_SINE = 0, NEGATIVE_COSINE = 0, USE_LUT_FILE = 1)
    