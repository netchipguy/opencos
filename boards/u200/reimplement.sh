#!/bin/bash

# SPDX-License-Identifier: MPL-2.0

# Call Vivado to execute the TCL part of the script

vivado -mode batch -source reimplement.tcl
