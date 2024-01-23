# SPDX-License-Identifier: MPL-2.0

# OC_BOARD_CONSTRAINTS.TCL -- OpenCOS constraint file for OC U200 projects, supplements vendor u200.xdc

puts "OC_BOARD_CONSTRAINTS.TCL: Start"

puts "OC_BOARD_CONSTRAINTS.TCL: Setting up managed clocks from board"
oc_add_clock USER_SI570_CLOCK 6.4 USER_SI570_CLOCK_P
oc_add_clock QSFP0_CLOCK 6.206 QSFP0_CLOCK_P
oc_add_clock QSFP1_CLOCK 6.206 QSFP1_CLOCK_P

puts "OC_BOARD_CONSTRAINTS.TCL: Running OC_AUTO_SCOPED_XDC"
# oc_auto_scoped_xdc

puts "OC_BOARD_CONSTRAINTS.TCL: Running OC_AUTO_ATTR_CONSTRAINTS"
# oc_auto_attr_constraints

puts "OC_BOARD_CONSTRAINTS.TCL: Running OC_AUTO_MAX_DELAY"
# oc_auto_max_delay

# this is a good place to put any pblocks that would likely apply to forks of this target
# TODO: make it such that IP pblocks are declared only if the IP is there, i.e. search for cells named uTOP/uBLAH...
if { ! [oc_is_run synth] } {
#    startgroup
#    create_pblock pblock_uBLAH
#    resize_pblock pblock_uBLAH -add CLOCKREGION_X0Y0:CLOCKREGION_X0Y3
#    add_cells_to_pblock pblock_uBLAH [get_cells [list uTOP/uBLAH]]
#    endgroup
}


if { [oc_is_run impl] } {
    puts "OC_BOARD_CONSTRAINTS.TCL: Fixing up vendor provided implementation constraints"

    # using -quiet because anything inside an if block will fail silently and be impossible to debug anyway

    set_property -quiet -dict { DRIVE 4 } [get_ports USB_UART_RX]
    set_property -quiet -dict { DRIVE 4 } [get_ports FPGA_TXD_MSP]

    set_property -quiet -dict { DRIVE 8 SLEW SLOW } [get_ports I2C_FPGA_S*]
    set_property -quiet -dict { DRIVE 8 SLEW SLOW } [get_ports I2C_MAIN_RESETN]
    set_property -quiet -dict { DRIVE 8 SLEW SLOW } [get_ports STATUS_LED*_FPGA]

    set_property -quiet -dict { DRIVE 8 } [get_ports QSFP0_* -filter {DIRECTION == OUT}]
    set_property -quiet -dict { DRIVE 8 } [get_ports QSFP1_* -filter {DIRECTION == OUT}]
}


if { [oc_is_run impl] } {
    puts "OC_BOARD_CONSTRAINTS.TCL: Setting up DBG_HUB"
    set_property C_CLK_INPUT_FREQ_HZ 100000000 [get_debug_cores dbg_hub]
    set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
    set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
    if { [llength [get_nets -quiet clockRef[0]]] } {
        connect_debug_port dbg_hub/clk [ get_nets clockRef[0] ]
        puts "OC_BOARD_CONSTRAINTS.TCL: Connected dbg_hub to clockRef[0]"
    } elseif { [llength [get_nets -quiet clockRef]] } {
        connect_debug_port dbg_hub/clk [ get_nets clockRef ]
        puts "OC_BOARD_CONSTRAINTS.TCL: Connected dbg_hub to clockRef"
    } else {
        puts "OC_BOARD_CONSTRAINTS.TCL: ERROR: couldn't find top clock for debug (tried clockRef and clockRef[0]) !!!"
    }
}

puts "OC_BOARD_CONSTRAINTS.TCL: Done"
