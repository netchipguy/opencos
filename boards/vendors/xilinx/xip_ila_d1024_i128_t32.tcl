
set ip_name "xip_ila_d1024_i128_t32"
set xci_file "${oc_projdir}/${oc_projname}.srcs/sources_1/ip/${ip_name}/${ip_name}.xci"
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name $ip_name
set_property -dict [list \
  CONFIG.C_ADV_TRIGGER {true} \
  CONFIG.C_INPUT_PIPE_STAGES {1} \
  CONFIG.C_NUM_OF_PROBES {2} \
  CONFIG.C_PROBE0_TYPE {1} \
  CONFIG.C_PROBE0_WIDTH {128} \
  CONFIG.C_PROBE1_WIDTH {32} \
  CONFIG.C_DATA_DEPTH {1024} \
] [get_ips ${ip_name}]

generate_target {all} [get_files "$xci_file"]
export_ip_user_files -of_objects [get_files "$xci_file"] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] "$xci_file"]

lappend ip_run_list "${ip_name}_synth_1"
lappend xci_file_list "${xci_file}"
