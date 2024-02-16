
set ip_name "xip_vio_i32_o32"
set xci_file "${oc_projdir}/${oc_projname}.srcs/sources_1/ip/${ip_name}/${ip_name}.xci"
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name $ip_name
set_property -dict [list \
  CONFIG.C_PROBE_IN0_WIDTH {32} \
  CONFIG.C_PROBE_OUT0_WIDTH {32} \
] [get_ips $ip_name]
generate_target {all} [get_files "$xci_file"]
export_ip_user_files -of_objects [get_files "$xci_file"] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] "$xci_file"]

lappend ip_run_list "${ip_name}_synth_1"
lappend xci_file_list "${xci_file}"
