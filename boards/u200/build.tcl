
# SPDX-License-Identifier: MPL-2.0

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

# leverage eda to generate an flist for everything under oc_chip_top
# TBD: does this same call get userspace app?  how?
# TBD: think about whether this is the right way to go, or whether "eda build" should build flist then run this script.
#      that approach would enable multiple targets in DEPS that build various flavors of the board, a convenient way
#      to distribute a bunch of preconfigured boards (i.e. various self-tests, example apps, etc)
# TBD: another way would be to have eda build command which can take direction via DEPS to launch a TCL and build a command
#      line for it.  Can this be 
exec python ${oc_root}/bin/eda flist oc_chip_top --out "[pwd]/build.flist" --force \
    +define+SYNTHESIS \
    +define+OC_LIBRARY_XILINX \
    +define+OC_BOARD_TOP_DEBUG \
    +define+OC_UART_CONTROL_INCLUDE_VIO_DEBUG \
    +define+OC_UART_CONTROL_INCLUDE_ILA_DEBUG \
    --no-emit-incdir \
    --prefix-define "oc_set_project_define " \
    --prefix-sv "add_files -norecurse " \
    --prefix-v "add_files -norecurse " \
    --prefix-vhd "add_files -norecurse "

source build.flist


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

source ${oc_root}/boards/vendors/xilinx/xip_vio_i32_o32.tcl
source ${oc_root}/boards/vendors/xilinx/xip_ila_d1024_i128_t32.tcl
source ${oc_root}/boards/vendors/xilinx/xip_ila_d8192_i128_t32.tcl

set tt "# ********************************"
set tt "# SYNTH design"
set tt "# ********************************"

reset_run synth_1
launch_runs synth_1 -jobs 6
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "ERROR: synth_1 failed"
}

set tt "# ********************************"
set tt "# IMPLEMENT design"
set tt "# ********************************"

launch_runs impl_1 -jobs 6
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

