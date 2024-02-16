
# SPDX-License-Identifier: MPL-2.0

set parallel_jobs 8

set tt "# ********************************"
set tt "# create a blank project"
set tt "# ********************************"

create_project u200 project -force

set tt "# ********************************"
set tt "# read in OC Vivado helper TCL"
set tt "# ********************************"

source "[pwd]/../vendors/xilinx/oc_vivado.tcl" -notrace

set tt "# ********************************"
set tt "# setup the board and part type"
set tt "# ********************************"

set_property BOARD_PART_REPO_PATHS "[pwd]/board" [current_project]
set_property board_part xilinx.com:au200:part0:1.2 [current_project]

set tt "# ********************************"
set tt "# setup the include dirs to OC normalized paths (+incdir+<oc_root>, everything else relative to there))"
set tt "# ********************************"

# should get these from eda flist probably, what if there are other incdirs we need?
# prob should add a function like oc_set_project_define, so that we are consistent in style and always get all filesets
set_property include_dirs $oc_root [current_fileset]
set_property include_dirs $oc_root [get_filesets sim_1]

set tt "# ********************************"
set tt "# add top level design files"
set tt "# ********************************"

source build.flist

set tt "# ********************************"
set tt "# check oc_chip_top is the top"
set tt "# ********************************"

if { [lsearch -exact [find_top] "oc_chip_top"] == -1 } {
    puts "ERROR: \[BUILD.TCL\] The top level is not oc_chip_top, prob there is a syntax error somewhere"
    exit -1
}

set tt "# ********************************"
set tt "# add top level constraint files"
set tt "# ********************************"

add_files -fileset constrs_1 -norecurse "$oc_root/boards/vendors/xilinx/oc_vivado.tcl"
set_property PROCESSING_ORDER EARLY [get_files -all "$oc_root/boards/vendors/xilinx/oc_vivado.tcl"]
add_files -fileset constrs_1 -norecurse "[pwd]/u200.xdc"
add_files -fileset constrs_1 -norecurse "[pwd]/oc_board_constraints.tcl"

# TEMP -- enable synth debug
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value -debug_log -objects [get_runs synth_1]

set tt "# ********************************"
set tt "# create required IP"
set tt "# ********************************"

config_ip_cache -use_cache_location ${oc_root}/boards/ip_cache

if { 0 } {
    source ${oc_root}/boards/vendors/xilinx/xip_vio_i32_o32.tcl
    source ${oc_root}/boards/vendors/xilinx/xip_ila_d1024_i128_t32.tcl
    source ${oc_root}/boards/vendors/xilinx/xip_ila_d8192_i128_t32.tcl
    source ${oc_root}/boards/vendors/xilinx/xip_iic.tcl
} else {
    set xci_file_list [list]
    set ip_run_list [list]
    set new_ip_method 1
    source ${oc_root}/boards/vendors/xilinx/source_before_ips.tcl
    source ${oc_root}/boards/vendors/xilinx/xip_vio_i32_o32.tcl
    source ${oc_root}/boards/vendors/xilinx/xip_ila_d1024_i128_t32.tcl
    source ${oc_root}/boards/vendors/xilinx/xip_ila_d8192_i128_t32.tcl
    source ${oc_root}/boards/vendors/xilinx/xip_iic.tcl
    source ${oc_root}/boards/vendors/xilinx/source_after_ips.tcl
}

set tt "# ********************************"
set tt "# SYNTH design"
set tt "# ********************************"

reset_run synth_1
launch_runs synth_1 -jobs $parallel_jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "ERROR: synth_1 failed"
}

set tt "# ********************************"
set tt "# IMPLEMENT design"
set tt "# ********************************"

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
