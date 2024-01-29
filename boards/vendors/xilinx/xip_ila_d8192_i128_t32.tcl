
set ip_name "xip_ila_d8192_i128_t32"
set xci_file "${oc_projdir}/${oc_projname}.srcs/sources_1/ip/${ip_name}/${ip_name}.xci"
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name $ip_name
set_property -dict [list \
  CONFIG.C_ADV_TRIGGER {true} \
  CONFIG.C_INPUT_PIPE_STAGES {1} \
  CONFIG.C_NUM_OF_PROBES {2} \
  CONFIG.C_PROBE0_TYPE {1} \
  CONFIG.C_PROBE0_WIDTH {128} \
  CONFIG.C_PROBE1_WIDTH {32} \
  CONFIG.C_DATA_DEPTH {8192} \
] [get_ips ${ip_name}]

generate_target {all} [get_files "$xci_file"]
export_ip_user_files -of_objects [get_files "$xci_file"] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] "$xci_file"]
launch_runs ${ip_name}_synth_1 -jobs 6
wait_on_run ${ip_name}_synth_1
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

