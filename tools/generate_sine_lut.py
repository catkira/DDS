import numpy as np
import argparse
import sys


def create_lut_file(filename, PHASE_DW, OUT_DW):
    MAX_OUT_VAL = 2**(OUT_DW - 1) - 1
    k = 0
    f = open(filename,'w')
    for p in range(int(2**PHASE_DW)):
        lut_val = int(np.round(np.sin(2 * np.pi *  p / (2**PHASE_DW) / 4) * MAX_OUT_VAL))
        #print(F"sin({2 * np.pi * p / (2**PHASE_DW)}) = {np.sin(2 * np.pi * p / (2**PHASE_DW))}  lut_val = {lut_val}")
        if k % 8 == 0:
            if k != 0:
                f.write("\n")
            f.write(F"@{k:08x} ")
        f.write("{0:0{1}x} ".format(lut_val,int(np.ceil(OUT_DW/4))))
        k += 1
    f.close()


def main(args):
    PHASE_DW = 8
    OUT_DW = 8
    filename = "sin_lut.hex"
    print(sys.argv)

    parser = argparse.ArgumentParser(description='creates lut table for DDS core')
    parser.add_argument('--filename', metavar='path', required=False, default = 'sine_lut.hex', help='lut filename')
    parser.add_argument('--PHASE_DW', metavar='path', required=False, default = 8, help='phase data width')
    parser.add_argument('--OUT_DW', metavar='path', required=False, default = 8, help='output data width')
    args = parser.parse_args(args)

    create_lut_file(args.filename, int(args.PHASE_DW), int(args.OUT_DW))

if __name__ == "__main__":
    main(sys.argv[1:])