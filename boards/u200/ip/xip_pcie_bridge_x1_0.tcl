
set ip_name "xip_pcie_bridge_x1_0"
set xci_file "${oc_projdir}/${oc_projname}.srcs/sources_1/ip/${ip_name}/${ip_name}.xci"
create_ip -name xdma -vendor xilinx.com -library ip -version 4.1 -module_name $ip_name
set_property -dict [list \
  CONFIG.dma_reset_source_sel {User_Reset} \
  CONFIG.en_gt_selection {true} \
  CONFIG.functional_mode {AXI_Bridge} \
  CONFIG.mode_selection {Advanced} \
  CONFIG.pcie_blk_locn {X1Y2} \
  CONFIG.pf0_Use_Class_Code_Lookup_Assistant {true} \
  CONFIG.pf0_bar0_64bit {true} \
  CONFIG.pf0_bar2_enabled {false} \
  CONFIG.pf0_bar2_scale {Kilobytes} \
  CONFIG.pf0_base_class_menu {Processing_accelerators} \
  CONFIG.pf0_device_id {0c0c} \
  CONFIG.pf0_subsystem_id {0c0c} \
  CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
  CONFIG.select_quad {GTY_Quad_227} \
] [get_ips $ip_name]

generate_target {all} [get_files "$xci_file"]
export_ip_user_files -of_objects [get_files "$xci_file"] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] "$xci_file"]

if { $new_ip_method } {
    lappend ip_run_list "${ip_name}_synth_1"
    lappend xci_file_list "${xci_file}"
} else {
    launch_runs ${ip_name}_synth_1 -jobs ${parallel_jobs}
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
}

# when including different flavors of IP TCL, we set defines to tell RTL what to expect, to avoid
# user having to align both manually
oc_set_project_define OC_IP_PCIE_0_MODULE=xip_pcie_bridge_x1_0
oc_set_project_define OC_IP_PCIE_1_MODULE=xip_pcie_bridge_x1_1
oc_set_project_define OC_IP_PCIE_M_AXIB_TYPE=oclib_pkg::axi4m_64_s
oc_set_project_define OC_IP_PCIE_M_AXIB_FB_TYPE=oclib_pkg::axi4m_64_fb_s
