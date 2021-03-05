from fixedpoint import FixedPoint
from bitstring import BitArray

import math
import numpy as np

class Model:
    def __init__(self, PHASE_DW, OUT_DW, USE_TAYLOR, LUT_DW):
        self.PHASE_DW = PHASE_DW
        self.OUT_DW = OUT_DW
        self.USE_TAYLOR = USE_TAYLOR
        self.LUT_DW = LUT_DW
                
        self.data_out_buf = np.zeros(self.extra_delay+1)
        self.out_valid = np.zeros(self.extra_delay+1)
        self.in_valid = 0
        self.data_in_buf = 0
        self.extra_delay = 3


    def set_data(self, data_in):
        self.data_in_buf = data_in
        self.in_valid = 1
        
    def reset(self):
        self.data_out_buf = np.zeros(self.extra_delay+1)
        self.out_valid = np.zeros(self.extra_delay+1)
        self.in_valid = 0
        self.data_in_buf = 0
        
    def tick(self):

        if self.in_valid == 1:
            self.out_valid[0] = 1
            self.in_valid = 0
        
        self.data_out_buf[0] = np.sin(self.data_in_buf*2*np.pi) * (2**(OUT_DW-1)-1)
        for i in np.arange(self.extra_delay-1,-1,-1):
            self.data_out_buf[i+1] = self.data_out_buf[i]
            self.out_valid[i+1] = self.out_valid[i] 
            
            
    
