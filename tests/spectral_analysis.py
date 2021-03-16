import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer
from cocotb.triggers import RisingEdge, ReadOnly

import random
import warnings
import os
import logging
import cocotb_test.simulator
import math
import numpy as np
import matplotlib.pyplot as plt

import importlib.util

CLK_PERIOD_NS = 2
CLK_PERIOD_S = CLK_PERIOD_NS * 1E-9

def dB20(array):
    with np.errstate(divide='ignore'):
        return 20 * np.log10(array)
        
def dB10(array):
    with np.errstate(divide='ignore'):
        return 10 * np.log10(array)        

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

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)        

        self.input = []
        f_mhz = 20.0001
        f_clk = 1/CLK_PERIOD_S
        self.accum_width = 32
        self.phase_increment = np.uint32(round((1<<self.accum_width)/(f_clk/(f_mhz*1E6))))

        tests_dir = os.path.abspath(os.path.dirname(__file__))
        model_dir = os.path.abspath(os.path.join(tests_dir, '../model/dds_model.py'))
        spec = importlib.util.spec_from_file_location("dds_model", model_dir)
        foo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(foo)
        self.model = foo.Model(self.PHASE_DW, self.OUT_DW, self.USE_TAYLOR, self.LUT_DW, self.SIN_COS, self.NEGATIVE_SINE, self.NEGATIVE_COSINE) 
        cocotb.fork(Clock(self.dut.clk, CLK_PERIOD_NS, units='ns').start())
        cocotb.fork(self.model_clk(CLK_PERIOD_NS, 'ns'))    
          
    async def model_clk(self, period, period_units):
        timer = Timer(period, period_units)
        while True:
            self.model.tick()
            await timer

    async def generate_input(self):
        phase = 0
        self.input = []
        accumulator = np.uint32(0)
        while True:

            await RisingEdge(self.dut.clk)
            self.model.set_data(phase) 
            self.input.append(phase)
            self.dut.s_axis_phase_tdata <= int(phase)
            self.dut.s_axis_phase_tvalid <= 1
            
            with np.errstate(over='ignore'):
                accumulator += self.phase_increment
            phase = (accumulator >> (self.accum_width - self.PHASE_DW)) & ((1 << self.PHASE_DW)-1)
            #print(F"accum = {accumulator}   phase = {phase}")

    async def cycle_reset(self):
        self.dut.s_axis_phase_tvalid <= 0
        self.dut.reset_n <= 0
        await RisingEdge(self.dut.clk)
        self.dut.reset_n <= 0
        await RisingEdge(self.dut.clk)
        self.dut.reset_n <= 1
        await RisingEdge(self.dut.clk)
        self.model.reset()
        
        
@cocotb.test()
async def simple_spectrum(dut):
    tb = TB(dut)
    await tb.cycle_reset()
    num_items = 500*2**tb.accum_width//tb.phase_increment  # n complete waves
    #num_items = 2**int(dut.PHASE_DW)//tb.freq//2  # one half wave
    #num_items = 1000
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

        if dut.m_axis_out_sin_tvalid == 1:
            a=dut.m_axis_out_sin_tdata.value.integer
            if (a & (1 << (tb.OUT_DW - 1))) != 0:
                a = a - (1 << tb.OUT_DW)
            output.append(int(a))
            if tb.SIN_COS:
                a=dut.m_axis_out_cos_tdata.value.integer
                if (a & (1 << (tb.OUT_DW - 1))) != 0:
                    a = a - (1 << tb.OUT_DW)
            else:
                a=0
            output_cos.append(int(a))
            #print(f"hdl: \t[{len(output)-1}]\t {output[-1]} \t {output_cos[-1]} ")
        #print(f"{int(tb.model.data_valid())} {dut.m_axis_out_tvalid}")
        count += 1
    if False:
        with open('../../out_sin.txt', 'w') as outfile:
            np.savetxt(outfile, output, fmt='%d')
        with open('../../out_cos.txt', 'w') as outfile:
            np.savetxt(outfile, output_cos, fmt='%d')
        with open('../../out_model_sin.txt', 'w') as outfile:
            np.savetxt(outfile, output_model, fmt='%d')
        with open('../../out_model_cos.txt', 'w') as outfile:
            np.savetxt(outfile, output_model_cos, fmt='%d')
    if True:
        fig1 = plt.figure()
        plt.plot(range(len(output)),output)
        #plt.plot(range(len(output_model)),output_model)
        fig2 = plt.figure()
        output_float = np.array(output) / (2**(tb.OUT_DW-1)-1)
        S = np.fft.fftshift(np.fft.fft(output_float))
        freq = np.fft.fftshift(np.fft.fftfreq(n=len(output_float), d=CLK_PERIOD_S))
        tiny_offset = 1E-10
        ydata = dB20(np.abs(S+tiny_offset)/(len(output_float)))
        plt.plot(freq,ydata)
        plt.ylim(np.maximum(-200,ydata.min()), ydata.max()+10)        
        fig3 = plt.figure()
        ydata_onesided = ydata[int(len(ydata)/2):] + 6
        ydata_onesided[0] -= 6
        plt.plot(freq[int(len(ydata)/2):],ydata_onesided)
        plt.ylim(np.maximum(-200,ydata_onesided.min()), ydata_onesided.max()+10)        
        plt.show()
    for i in range(num_items):
        assert np.abs(output[i] - output_model[i]) <= tolerance, f"[{i}] hdl: {output[i]} \t model: {output_model[i]}"
        if tb.SIN_COS:
            assert np.abs(output_cos[i] - output_model_cos[i]) <= tolerance, f"[{i}] hdl: {output_cos[i]} \t model: {output_model_cos[i]}"
    #print(f"received {len(output)} samples")
    gen.kill()
    tb.dut.s_axis_phase_tvalid <= 0
# cocotb-test
    