
# SPDX-License-Identifier: MPL-2.0

set script_path [ file dirname [ file normalize [ info script ] ] ]
set parallel_jobs 8
set proj_dir "project"
set proj_name "u200"
set flist_file "build.flist"

if { $argc > 0 } { set proj_dir   [lindex $argv 0] }
if { $argc > 1 } { set flist_file [lindex $argv 1] }
if { $argc > 2 } { error "Too many command line arguments to build.tcl, expect <proj_dir> and <flist_file> at most" }

puts "proj_name:  $proj_name"
puts "proj_dir:   $proj_dir"
puts "flist_file: $flist_file"

set tt "# ********************************"
set tt "# create a blank project"
set tt "# ********************************"

create_project $proj_name $proj_dir -force

set tt "# ********************************"
set tt "# read in OC Vivado helper TCL"
set tt "# ********************************"

source "${script_path}/../vendors/xilinx/oc_vivado.tcl" -notrace

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

source ${flist_file}
# we only want this set in the design context
oc_set_design_define SYNTHESIS

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

add_files -fileset constrs_1 -norecurse "${oc_root}/boards/vendors/xilinx/oc_vivado.tcl"
set_property PROCESSING_ORDER EARLY [get_files -all "${oc_root}/boards/vendors/xilinx/oc_vivado.tcl"]
add_files -fileset constrs_1 -norecurse "${script_path}/u200.xdc"
add_files -fileset constrs_1 -norecurse "${script_path}/oc_board_constraints.tcl"

# TEMP -- enable synth debug
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value -debug_log -objects [get_runs synth_1]

set tt "# ********************************"
set tt "# create required IP"
set tt "# ********************************"

config_ip_cache -use_cache_location "${oc_root}/boards/vendors/xilinx/ip_cache"

set xci_file_list [list]
set ip_run_list [list]
set new_ip_method 1
source ${oc_root}/boards/vendors/xilinx/source_before_ips.tcl
source ${oc_root}/boards/vendors/xilinx/xip_vio_i32_o32.tcl
source ${oc_root}/boards/vendors/xilinx/xip_ila_d1024_i128_t32.tcl
source ${oc_root}/boards/vendors/xilinx/xip_ila_d1024_i512_t32.tcl
source ${oc_root}/boards/vendors/xilinx/xip_ila_d8192_i128_t32.tcl
source ${oc_root}/boards/vendors/xilinx/xip_iic.tcl
source ${oc_root}/boards/u200/ip/xip_pcie_bridge_x1_0.tcl
source ${oc_root}/boards/u200/ip/xip_ddr4.tcl
source ${oc_root}/boards/vendors/xilinx/source_after_ips.tcl

set tt "# ********************************"
set tt "# add top level simulation files"
set tt "# ********************************"

add_files -fileset sim_1 -norecurse "${script_path}/tests/oc_chip_harness.sv"
add_files -fileset sim_1 -norecurse "${oc_root}/top/tests/oc_cos_test.sv"
add_files -fileset sim_1 -norecurse "${oc_root}/sim/ocsim_clock.sv"
add_files -fileset sim_1 -norecurse "${oc_root}/sim/ocsim_reset.sv"
add_files -fileset sim_1 -norecurse "${oc_root}/sim/ocsim_uart.sv"
add_files -fileset sim_1 -norecurse "${oc_root}/sim/ocsim_axim_source.sv"
oc_set_sim_define OC_CHIP_HARNESS_TEST
oc_set_sim_define SIMULATION

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

set runs_dir "${script_path}/${proj_dir}/${proj_name}.runs"

open_checkpoint "${runs_dir}/impl_1/oc_chip_top_routed.dcp"

report_route_status -file "${runs_dir}/impl_1/${proj_name}_route_status.rpt"
report_timing -file "${runs_dir}/impl_1/${proj_name}_timing.rpt"
report_utilization -file "${runs_dir}/impl_1/${proj_name}_util.rpt"
report_utilization -hierarchical -hierarchical_depth 10 -file "${runs_dir}/impl_1/${proj_name}_hier_util.rpt"

set tt "# ********************************"
set tt "# Create bitstream"
set tt "# ********************************"

write_bitstream -force "${runs_dir}/impl_1/${proj_name}.bit"
set_msg_config -id {Chipscope 16-155} -suppress
write_debug_probes -force "${runs_dir}/impl_1/${proj_name}.ltx"
write_cfgmem  -format mcs -size 128 -interface SPIx4 -loadbit "up 0x01002000 ${runs_dir}/impl_1/${proj_name}.bit" \
    -force -file "${runs_dir}/impl_1/${proj_name}.mcs"
write_mem_info -force "${runs_dir}/impl_1/${proj_name}.mmi"
