
# SPDX-License-Identifier: MPL-2.0

set parallel_jobs 8

set tt "# ********************************"
set tt "# create a blank project"
set tt "# ********************************"

open_project project/u200.xpr

set tt "# ********************************"
set tt "# read in OC Vivado helper TCL"
set tt "# ********************************"

source "[pwd]/../vendors/xilinx/oc_vivado.tcl" -notrace

set tt "# ********************************"
set tt "# IMPLEMENT design"
set tt "# ********************************"

reset_run impl_1
launch_runs impl_1 -jobs $parallel_jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: impl_1 failed"
}

set tt "# ********************************"
set tt "# Create reports"
set tt "# ********************************"

open_checkpoint "project/u200.runs/impl_1/oc_chip_top_routed.dcp"

report_route_status 
report_timing
report_utilization

set tt "# ********************************"
set tt "# Create bitstream"
set tt "# ********************************"

write_bitstream -force "project/u200.runs/impl_1/oc_chip_top.bit"
set_msg_config -id {Chipscope 16-155} -suppress
write_debug_probes -force "project/u200.runs/impl_1/oc_chip_top.ltx"
