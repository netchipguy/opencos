
# SPDX-License-Identifier: MPL-2.0

# ********************************
# create a blank project
# ********************************
create_project u200 project -force

# ********************************
# read in OC Vivado helper TCL
# ********************************
source "[pwd]/../vendors/xilinx/oc_vivado.tcl" -notrace

# ********************************
# setup the board and part type
# ********************************
set_property BOARD_PART_REPO_PATHS "[pwd]/board" [current_project]
set_property board_part xilinx.com:au200:part0:1.2 [current_project]

# ********************************
# setup the include dirs to OC normalized paths (+incdir+<oc_root>, everything else relative to there))
# ********************************
set_property include_dirs $oc_root [current_fileset]
set_property include_dirs $oc_root [get_filesets sim_1]

oc_set_project_define "OC_BOARD_TOP_DEBUG"

# ********************************
# add top level design files
# ********************************

# leverage eda to generate an flist for everything under oc_chip_top
exec python ${oc_root}/bin/eda flist oc_chip_top --out "[pwd]/build.flist" --force \
    --no-emit-incdir \
    --prefix-define "oc_set_project_define " \
    --prefix-sv "add_files -norecurse " \
    --prefix-v "add_files -norecurse " \
    --prefix-vhd "add_files -norecurse "

source build.flist


# ********************************
# add top level constraint files
# ********************************

add_files -fileset constrs_1 -norecurse "$oc_root/boards/vendors/xilinx/oc_vivado.tcl"
set_property PROCESSING_ORDER EARLY [get_files -all "$oc_root/boards/vendors/xilinx/oc_vivado.tcl"]
add_files -fileset constrs_1 -norecurse "[pwd]/u200.xdc"
add_files -fileset constrs_1 -norecurse "[pwd]/oc_board_constraints.tcl"

# TEMP -- enable synth debug
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value -debug_log -objects [get_runs synth_1]

# ********************************
# create required IP
# ********************************

set ip_name "xip_vio_i32_o32"
set xci_file "${oc_projdir}/${oc_projname}.srcs/sources_1/ip/${ip_name}/${ip_name}.xci"
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name $ip_name
set_property -dict [list \
  CONFIG.C_PROBE_IN0_WIDTH {32} \
  CONFIG.C_PROBE_OUT0_WIDTH {32} \
  CONFIG.Component_Name {$ip_name} \
] [get_ips $ip_name]
generate_target {all} [get_files "$xci_file"]
export_ip_user_files -of_objects [get_files "$xci_file"] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] "$xci_file"]
launch_runs ${ip_name}_synth_1 -jobs 6
# should perhaps create a list of IPs and wait on them all :)
wait_on_run ${ip_name}_synth_1
# and then I guess export them all, should check how long this takes, and the size, maybe we don't want to build everything every time...
export_simulation -of_objects [get_files "$xci_file"] \
    -directory "${oc_projdir}/${oc_projname}.ip_user_files/sim_scripts" \
    -ip_user_files_dir "${oc_projdir}/${oc_projname}.ip_user_files" \
    -ipstatic_source_dir "${oc_projdir}/${oc_projname}.ip_user_files/ipstatic" \
    -lib_map_path [list {"modelsim=${oc_projdir}/${oc_projname}.cache/compile_simlib/modelsim"} \
                       {"questa=${oc_projdir}/${oc_projname}.cache/compile_simlib/questa"} \
                       {"xcelium=${oc_projdir}/${oc_projname}.cache/compile_simlib/xcelium"} \
                       {"vcs=${oc_projdir}/${oc_projname}.cache/compile_simlib/vcs"} \
                       {"riviera=${oc_projdir}/${oc_projname}.cache/compile_simlib/riviera"}] \
    -use_ip_compiled_libs -force -quiet

# ********************************
# finally, implement the design
# ********************************

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
