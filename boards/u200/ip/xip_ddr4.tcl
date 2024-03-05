
set ip_name "xip_ddr4"
set xci_file "${oc_projdir}/${oc_projname}.srcs/sources_1/ip/${ip_name}/${ip_name}.xci"

create_ip -name ddr4 -vendor xilinx.com -library ip -version 2.2 -module_name $ip_name

# User Parameters
set_property -dict [list \
  CONFIG.ADDN_UI_CLKOUT1_FREQ_HZ {None} \
  CONFIG.C0.DDR4_AUTO_AP_COL_A3 {true} \
  CONFIG.C0.DDR4_AxiAddressWidth {34} \
  CONFIG.C0.DDR4_AxiDataWidth {512} \
  CONFIG.C0.DDR4_AxiSelection {true} \
  CONFIG.C0.DDR4_CasLatency {17} \
  CONFIG.C0.DDR4_Ecc {true} \
  CONFIG.C0.DDR4_Mem_Add_Map {ROW_COLUMN_BANK_INTLV} \
  CONFIG.C0.DDR4_MemoryPart {MTA18ASF2G72PZ-2G3} \
  CONFIG.C0.DDR4_MemoryType {RDIMMs} \
  CONFIG.C0.DDR4_TimePeriod {833} \
  CONFIG.C0_DDR4_BOARD_INTERFACE {Custom} \
  CONFIG.Debug_Signal {Disable} \
] [get_ips $ip_name]

generate_target {all} [get_files "$xci_file"]
export_ip_user_files -of_objects [get_files "$xci_file"] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] "$xci_file"]

lappend ip_run_list "${ip_name}_synth_1"
lappend xci_file_list "${xci_file}"
