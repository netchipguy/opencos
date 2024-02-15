#!/bin/bash

# SPDX-License-Identifier: MPL-2.0

# leverage eda to generate an flist for everything under oc_chip_top
# TBD: does this same call get userspace app?  how?
# TBD: think about whether this is the right way to go, or whether "eda build" should build flist then run this script.
#      that approach would enable multiple targets in DEPS that build various flavors of the board, a convenient way
#      to distribute a bunch of preconfigured boards (i.e. various self-tests, example apps, etc)
# TBD: another way would be to have eda build command which can take direction via DEPS to launch a TCL and build a command
#      line for it.

python3 ../../bin/eda flist oc_chip_top --out "./build.flist" --force \
    +define+SYNTHESIS \
    +define+OC_LIBRARY_XILINX \
    +define+OC_LIBRARY_ULTRASCALE_PLUS \
    +define+OC_BOARD_TOP_DEBUG \
    +define+OC_UART_CONTROL_INCLUDE_VIO_DEBUG \
    +define+OC_UART_CONTROL_INCLUDE_ILA_DEBUG \
    --no-emit-incdir \
    --no-quote-define \
    --prefix-define "oc_set_project_define " \
    --prefix-sv "add_files -norecurse " \
    --prefix-v "add_files -norecurse " \
    --prefix-vhd "add_files -norecurse "

# Call Vivado to execute the TCL part of the script

vivado -mode batch -source build.tcl
