PWD     =  $(shell pwd)
SIM     ?=  verilator
VERILATOR_TRACE = 1

DUT         = dds
TOPLEVEL    = $(DUT)
MODULE      = spectral_analysis

VERILOG_SOURCES = $(PWD)/../hdl/$(DUT).sv

# module parameters
export PHASE_DW      ?= 16
export OUT_DW        ?= 16
export USE_TAYLOR    ?= 1
export LUT_DW        ?= 9
export SIN_COS       ?= 0
export NEGATIVE_SINE ?= 0
export NEGATIVE_COSINE ?= 0

# for verilator and icarus
COMPILE_ARGS += -DLUT_PATH=\"$(PWD)/../hdl/\"

ifeq ($(SIM), verilator)
    EXTRA_ARGS += $(PWD)/verilator_waiver.vlt
	#COMPILE_ARGS += -Wno-SELRANGE -Wno-WIDTH -Wno-CASEINCOMPLETE

	COMPILE_ARGS += -GPHASE_DW=$(PHASE_DW)
	COMPILE_ARGS += -GOUT_DW=$(OUT_DW)
	COMPILE_ARGS += -GUSE_TAYLOR=$(USE_TAYLOR)
	COMPILE_ARGS += -GLUT_DW=$(LUT_DW)
	COMPILE_ARGS += -GSIN_COS=$(SIN_COS)
	COMPILE_ARGS += -GNEGATIVE_SINE=$(NEGATIVE_SINE)
	COMPILE_ARGS += -GNEGATIVE_COSINE=$(NEGATIVE_COSINE)
endif


include $(shell cocotb-config --makefiles)/Makefile.sim