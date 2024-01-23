
# SPDX-License-Identifier: MPL-2.0

create_project oc_u200 project -force

# read in OC Vivado helper TCL
source [pwd]/../vendors/xilinx/oc_vivado.tcl -notrace

set_property BOARD_PART_REPO_PATHS [pwd]/board [current_project]
set_property board_part xilinx.com:au200:part0:1.2 [current_project]

set_property include_dirs $oc_root [current_fileset]
set_property include_dirs /home/simon/opencos [get_filesets sim_1]

add_files -norecurse [pwd]/oc_chip_top.sv

add_files -fileset constrs_1 -norecurse $oc_root/boards/vendors/xilinx/oc_vivado.tcl
set_property PROCESSING_ORDER EARLY [get_files -all $oc_root/boards/vendors/xilinx/oc_vivado.tcl]
add_files -fileset constrs_1 -norecurse [pwd]/u200.xdc
add_files -fileset constrs_1 -norecurse [pwd]/oc_board_constraints.tcl

set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value -debug_log -objects [get_runs synth_1]

reset_run synth_1
launch_runs synth_1 -jobs 6
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "ERROR: synth_1 failed"
}

launch_runs impl_1 -jobs 6
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: impl_1 failed"
}

launch_runs impl_1 -to_step write_bitstream -jobs 6
wait_on_run impl_1
