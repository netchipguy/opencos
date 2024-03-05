
# SPDX-License-Identifier: MPL-2.0

# OC_VIVADO.TCL -- Generic support for Vivado, shared by all Xilinx targets

puts "OC_VIVADO.TCL: START"

# *******************************************
# Describe the design before calling the oc_auto* functions
# *******************************************

variable oc_root
variable oc_projdir
variable oc_projname
variable oc_clocks

# the goal of this func is to cause a warning to be shown in the Vivado GUI, so we trigger a fake warning about a pin
# whose name tells us what issue caused the warning
proc oc_throw_warning { w } {
    get_pins ${w}
}

# expected to be called by the chip_constraints.tcl master constraint file
proc oc_add_clock { clockname {period 0} {pinport ""}} {
    global oc_clocks
    if { $period != 0 } {
        # we are being asked to create a clock
        if { [llength [get_pins $pinport -quiet]] } {
            # and we've been given a pin name
            set obj [get_pins $pinport]
            set objtype "pin"
        } elseif { [llength [get_ports $pinport -quiet]] } {
            # and we've been given a port name
            set obj [get_ports $pinport]
            set objtype "port"
        } else {
            puts "OC_ADD_CLOCK WARNING: Tried to clock $clockname (period ${period}ns) on $pinport, which doesn't seem to exist"
            oc_throw_warning OC_ADD_CLOCK_WARNING_${clockname}_DOESNT_EXIST ;  return
        }
        puts "OC_ADD_CLOCK INFO: Adding clock $clockname (period ${period}ns) on $objtype $pinport"
        if { [llength [get_clocks -of $obj -quiet]] > 1 } {
            puts "OC_ADD_CLOCK ERROR: Cannot handle multiple clocks already there: [get_clocks $obj]"
            oc_throw_warning OC_ADD_CLOCK_ERROR_MULTIPLE_MATCH ;  return
        } elseif { [llength [get_clocks -of $obj -quiet]] } {
            # there is already a clock on this object, we are just going to create an alias
            set oldclock [ get_clocks -of $obj ]
            set oldperiod [ get_property PERIOD $oldclock ]
            puts "OC_ADD_CLOCK INFO: A clock already is declared on this $objtype: $oldclock (period ${oldperiod}ns)"
            if { $oldclock == $clockname } {
                if { $oldperiod == $period } {
                    puts "OC_ADD_CLOCK INFO: Since the requested clock already exists, not doing anything"
                } else {
                    puts "OC_ADD_CLOCK ERROR: The requested clock already exists with a different period ${oldperiod}ns"
                    oc_throw_warning OC_ADD_CLOCK_ERROR_${clockname}_ALREADY_EXISTS ;  return
                }
            } else {
                if { $oldperiod == $period } {
                    puts "OC_ADD_CLOCK INFO: Creating generated clock $clockname on $objtype $pinport, renaming $oldclock"
                    set newclk [create_generated_clock -name $clockname $obj -quiet]
                    if { $newclk != $clockname } {
                        puts "OC_ADD_CLOCK WARNING: Failed to generate clock, this is probably already a master clock, not a generated clock."
                        puts "OC_ADD_CLOCK WARNING: Since a new clock cannot be declared here, and existing clock has same frequency, OC will"
                        puts "OC_ADD_CLOCK WARNING: use the existing clock ($oldclock) instead of the name given to oc_add_clock ($clockname)"
                        set clockname $oldclock
                    }
                } else {
                    puts "OC_ADD_CLOCK ERROR: the existing clock has a different period ${oldperiod}ns, inconsistent constraints"
                    oc_throw_warning OC_ADD_CLOCK_ERROR_${clockname}_INCONSISTENT_PERIOD ;  return
                }
            }
        } else {
            # this clock has not been defined by the vendor provided XDC, so we do a create_clock here
            puts "OC_ADD_CLOCK INFO: Creating new clock $clockname period $period on $objtype $pinport"
            create_clock -period $period -name $clockname $obj
        }
    }
    puts "OC_ADD_CLOCK INFO: adding clock $clockname to oc_clocks, for OC TCL smart constraints"
    lappend oc_clocks $clockname
}


# *******************************************
# Offload most of the manual stuff that would go into the per-chip XDC/SDC/TCL
# *******************************************

# this will bind scoped XDC files with the library elements that need them
# expected to be called by the chip_constrings.tcl master constraint file
proc oc_auto_scoped_xdc {} {
    global oc_root
    # handling some constraints via scoped XDC, which seems like a good way to do things, but has limitations
    # that XDC language is more limited than TCL, and debugging the scoped XDC can be a pain
    read_xdc -ref oclib_uart_rx ${oc_root}/lib/oclib_uart_rx.xdc -unmanaged
    read_xdc -ref oclib_uart_tx ${oc_root}/lib/oclib_uart_tx.xdc -unmanaged
}

# this will add all programmatic timing constraints not handled by scoped XDC above
# expected to be called by the chip_constraints.tcl master constraint file
proc oc_auto_attr_constraints {} {

    puts "STARTING AUTO_ATTR_CONSTRAINTS"

    # this is an alternative to the scoped XDC, and could be improved by moving this into an oc_pll.tcl perhaps,
    # to emulate the modularity of scoped XDC, while retaining full power of TCL.  This is nice because TCL can
    # do things like query the design via attributes (clock freq, number of clocks, enablement of features) and
    # then adjust the constraints accordingly
    oc_auto_oclib_reset
    oc_auto_oc_pll
    oc_auto_oc_cmac

    # we support attributes in the RTL, which "request" timing rules to be applied to the code.  This is finer-grained
    # than the per-module "scoped" XDC (or even TCL) and is the way we'll support false paths, multicycle paths, etc, in libraries
    # and user logic.  It's nice that the constraint is applied right in the RTL. 
    oc_auto_attr_max_skew_ns

    puts "FINISHED AUTO_ATTR_CONSTRAINTS"
}

# this will create default max_paths of 20ns between OC-managed clocks.  This assumes that all clocks are basically async
# max_delay will be supplemented by any bus_skew, etc, constraints that have been added by the above processes expected to be
# called by the chip_constraints.tcl master constraint file
# TBD: may want to add option to include generated clocks via args here, since this is called by target-specific chip_constraints
# which would be aware of tricky situations with generated clocks (to say allow enumerating the generated clocks under a certain refclk,
# but not others)
proc oc_auto_max_delay { } {
    global oc_clocks
    foreach from_clock $oc_clocks {
        foreach to_clock $oc_clocks {
            if { $from_clock != $to_clock } {
                puts "OC_AUTO_MAX_DELAY: adding set_max_delay from $from_clock to $to_clock"
                set_max_delay -datapath_only -from [get_clocks $from_clock] \
                    -to   [get_clocks $to_clock] -delay 20.0
            }
        }
    }
}

# *******
# the reminaing functions in the oc_auto_* group are not expected to be called directly from chip_constraints.tcl master constraint file

# add constraints for oclib_reset(s)
proc oc_auto_oclib_reset {} {
    set instances [oc_get_instances oclib_reset]
    foreach inst $instances {
        puts "OC_AUTO_OCLIB_RESET: Found oclib_reset $inst"
        # we have an async path to the CLR pin of these flops.  May need to make this -quiet if the flop doesn't exit?
        set_max_delay -to [get_pins $inst/startPipe_reg[*]/CLR] 20.0
    }
}

# add constraints for oc_pll(s)
proc oc_auto_oc_pll {} {
    set instances [oc_get_instances oc_pll]
    set base_name "clk_pll"
    set iter 0
    foreach inst $instances {
        puts "OC_AUTO_OC_PLL: Found oc_pll $inst"
        if { [llength $instances] > 1 } { set base_name "clk_pll${iter}" }
        for { set i 0 } { $i < 7 } { incr i }  {  
            set clock_name ${base_name}_${i}
            # if already has a clock on the output pin, there'll be an unknown auto-gen clock; we provide a nicely named alias
            if { [llength [get_clocks -quiet -of_objects [get_pins $inst/uPLL/CLKOUT$i] ]] } {
                puts "OC_AUTO_OC_PLL: Calling create_generated_clock, adding OC clock $clock_name"
                create_generated_clock -name $clock_name [get_pins $inst/uPLL/CLKOUT$i]
                oc_add_clock $clock_name
            }
        }
        incr iter
    }
}

# add constraints for oc_cmac(s)
proc oc_auto_oc_cmac {} {
    set instances [oc_get_instances oc_cmac]
    set base_name "clk_cmac"
    set iter 0
    foreach inst $instances {
        puts "OC_AUTO_OC_CMAC: Found oc_cmac $inst"
        if { [llength $instances] > 1 } { set base_name "clk_cmac${iter}" }
        set clock_name [get_clocks -of_objects [get_pin $inst/clockAxi]]
        puts "OC_AUTO_OC_CMAC: Adding OC clock $clock_name"
        oc_add_clock $clock_name
        # would like to do a create_generated_clock as we do for PLL, but the source pin is buried so deep it's messy.  Need a
        # way to find the source pin and make it clean to rename the clock.  Better to have clk_cmac0_axi instead of txoutclk_out[0]
        incr iter
    }
}

# add constraints for RTL marked with OC_MAX_SKEW_NS
proc oc_auto_attr_max_skew_ns {} {
    # Handle skew bundles
    set skew_groups_done [dict create]
    # first find all the source flops that have OC_MAX_SKEW_NS attribute
    foreach cell [get_cells -quiet -hier -filter {OC_MAX_SKEW_NS > 0}] {
        set skew_group $cell
        set skew_ns [get_property OC_MAX_SKEW_NS [get_cells $cell]]
        # we remove trailing []'s to get the name for all the flops in a skew_group i.e. struct (skew group must be a single struct)
        while { [regexp {^(.*)\[\w*\]$} $skew_group full_match sub_match] } { set skew_group $sub_match }
        # now append * because we want to match all flops in the struct (all those []'s)
        append skew_group *
        # now that we've mapped the cell to a group, check whether the group has already been processed
        if { ! [dict exists $skew_groups_done $skew_group] } {
            dict set skew_groups_done $skew_group 1
            puts "OC_AUTO_SDC: Creating skew group $skew_group"
            # now we're going to find load pins for the $cell (one member of the group) and assume that whole group is going to the same destiantion(s)
            set source_pin $cell
            append source_pin "/Q"
            set dest_pins [oc_get_load_pins $source_pin]
            # it shouldn't be commmon (generally debug visibility) but we must handle the group going to multiple destinations...
            foreach dest_pin $dest_pins {
                # swallow trailing []'s and /D
                while { [regexp {^(.*)\[\w*\](/D)?$} $dest_pin full_match sub_match trailer] } { set dest_pin $sub_match }
                set dest_pin_group $dest_pin
                append dest_pin_group "*/D"
                # at this point dest_pin_group is something like uCORE/uSOME_DEST/uSYNC/sync_ff_reg*/D
                set_bus_skew -from [get_cells ${skew_group}] -to [get_pins ${dest_pin_group}] $skew_ns
            }
        }
    }
}




# *******************************************
# Tracing connections, drivers, loads
# *******************************************

# returns a list of all instances of a given module
proc oc_get_instances { module } {
    return [get_cells -hier * -quiet -filter "REF_NAME == $module || ORIG_REF_NAME == $module" ]
}

# returns a list of nets connected to a "thing" (which can be anything -- port, pin, net, etc)
proc oc_get_connected_nets {thing} {
    if { [llength [get_pins -quiet $thing]] } {
        return [ get_nets -segments -of_objects [get_pins $thing] ]
    } elseif { [llength [get_ports -quiet $thing]] } {
        return [ get_nets -segments -of_objects [get_ports $thing] ]
    } elseif { [llength [get_nets -quiet $thing]] } {
        return [ get_nets $thing]
    }
}

# returns a list of pins driving a "thing" (port, pin, net, etc)
proc oc_get_driving_pins {thing} {
    set nets [oc_get_connected_nets $thing]
    return [get_pins -quiet -of_objects $nets -filter {IS_LEAF && (DIRECTION == "OUT") }]
}

# returns a list of ports driving a "thing" (port, pin, net, etc)
proc oc_get_driving_ports {thing} {
    set nets [oc_get_connected_nets $thing]
    return [get_ports -quiet -of_objects $nets -filter {(DIRECTION == "IN") }]
}

# prints a human-readable list of pins and ports driving a "thing" (port, pin, net, etc)
proc oc_show_drivers {thing} {
    foreach pin [oc_get_driving_pins $thing] {
        puts "  pin: $pin"
    }
    foreach port [oc_get_driving_ports $thing] {
        puts " port: $port"
    }
}

# returns a list of pins that are driven by a "thing" (port, pin, net, etc)
proc oc_get_load_pins {thing} {
    set nets [oc_get_connected_nets $thing]
    return [get_pins -quiet -of_objects $nets -filter {IS_LEAF && (DIRECTION == "IN") }]
}

# returns a list of ports that are driven by a "thing" (port, pin, net, etc)
proc oc_get_load_ports {thing} {
    set nets [oc_get_connected_nets $thing]
    return [get_ports -quiet -of_objects $nets -filter {(DIRECTION == "OUT") }]
}

# prints a human-readable list of pins and ports that are driven by a "thing" (port, pin, net, etc)
proc oc_show_loads {thing} {
    foreach pin [oc_get_load_pins $thing] {
        puts "  pin: $pin"
    }
    foreach port [oc_get_load_ports $thing] {
        puts " port: $port"
    }
}

# *******************************************
# Manipulate project defines
# *******************************************

proc oc_set_define_in_string { define_string name { value "" }} {
    set new_defines " " ; # we will always have a trailing space, dropping it at the end
    set done 0
    foreach d $define_string {
        if { [ regexp {(\w+)\=(.*)} $d fullmatch d_name d_value ] } {
            if { $d_name == $name } {
                if { $value != "" } { append new_defines "${name}\=${value} "
                } else { append new_defines "${name} " }
                set done 1
            } else { append new_defines "${d_name}\=${d_value} " }
        } else {
            if { $d == $name } {
                if { $value != "" } { append new_defines "${name}\=${value} "
                } else { append new_defines "${name} " }
                set done 1
            } else { append new_defines "${d} " }
        }
    }
    if { $done == 0 } {
        if { $value != "" } { append new_defines "${name}\=${value} "
        } else { append new_defines "${name} " }
    }
    return [string trim $new_defines]
}

proc oc_clear_define_in_string { define_string name } {
    set new_defines " " ; # we will always have a trailing space, dropping it at the end
    foreach d $define_string {
        if { [ regexp {(\w+)\=(.*)} $d fullmatch d_name d_value ] } {
            if { $d_name != $name } { append new_defines "${d_name}\=${d_value} " }
        } else {
            if { $d != $name } { append new_defines "${d} " }
        }
    }
    return [string trim $new_defines]
}

proc oc_get_project_defines { { fileset "sources_1"}  } {
    return [get_property verilog_define [get_fileset $fileset]]
}

proc oc_set_project_defines { define_string { fileset "sources_1" } } {
    set_property verilog_define $define_string [get_fileset $fileset]
}

proc oc_set_design_define { name { value "" }} {
    set new_defines [ oc_set_define_in_string [oc_get_project_defines [current_fileset] ] $name $value ]
    oc_set_project_defines $new_defines [current_filese] 
}

proc oc_clear_design_define { name } {
    set new_defines [ oc_clear_define_in_string [oc_get_project_defines [current_fileset] ] $name ]
    oc_set_project_defines $new_defines [current_fileset]
}

proc oc_set_sim_define { name { value "" }} {
    set new_defines [ oc_set_define_in_string [oc_get_project_defines [current_fileset -simset] ] $name $value ]
    oc_set_project_defines $new_defines [current_fileset -simset] 
}

proc oc_clear_sim_define { name } {
    set new_defines [ oc_clear_define_in_string [oc_get_project_defines [current_fileset -simset] ] $name ]
    oc_set_project_defines $new_defines [current_fileset -simset]
}

proc oc_set_project_define { name { value "" }} {
    oc_set_design_define $name $value
    oc_set_sim_define $name $value
}

proc oc_clear_project_define { name } {
    oc_clear_design_define $name
    oc_clear_sim_define $name
}

# *******************************************
# Hook some Vivado commands
# *******************************************

proc oc_set_build_defines {} {
    global oc_set_build_defines_done

    puts "OC_SET_BUILD_DEFINES: Creating OC_BUILD_* build stamps"
    # build uuid
    #    set uuid "128\\'h"  ; # Vivado can't seem to handle the single quote in a define, I've opened a support case
    set uuid ""
    set b 0
    set w 0
    for { set i 0 } { $i < 16 } { incr i } { 
        set r [expr {int(256*rand())}]
        if { $i == 6 } { set $r [expr {($r & 0xf0) | 0x40}] } ; # set Version 4 (Random)
        if { $i == 8 } { set $r [expr {($r & 0xc0) | 0x80}] } ; # set Variant 1 (RFC)
        append uuid [format "%02x" $r]
        if { $b==3 } {
            scan $uuid %x uuid ; # temporary
            oc_set_project_define "OC_BUILD_UUID$w" $uuid
            puts "OC_SET_BUILD_DEFINES: OC_BUILD_UUID$w      = $uuid"
            set uuid ""
            set b 0
            incr w
        } else {
            incr b
        }
    }

    # build date
    set t [clock seconds]
    #    set build_date [clock format $t -format "32\\'h%Y%m%d"]
    set build_date [clock format $t -format "%Y%m%d"] ; # temporary
    scan $build_date %x build_date ; # temporary
    oc_set_project_define "OC_BUILD_DATE" $build_date
    puts "OC_SET_BUILD_DEFINES: OC_BUILD_DATE      = $build_date"
    # build time
    #    set build_time [clock format $t -format "16\\'h%H%M"]
    set build_time [clock format $t -format "%H%M"] ; # temporary
    scan $build_time %x build_time ; # temporary
    oc_set_project_define "OC_BUILD_TIME" $build_time
    puts "OC_SET_BUILD_DEFINES: OC_BUILD_TIME      = $build_time"

    # once this is set, our hooks will not call this proc for implementation runs.  this is because changing
    # defines will cause synth to become out of date.  if the user just opens a project and clicks to generate
    # bitstream, however, launch_runs gets called with an "impl_xx" (and will call synthesis "under the hood")
    # so if we've never run the hooks, we do it even for implementation runs
    set oc_set_build_defines_done 1
}

proc oc_hook_vivado_open_project {} {
    global oc_hook_vivado_open_project_done
    # we only want to do this once
    if { ![info exists oc_hook_vivado_open_project_done] } {
        rename open_project oc_open_project_original
        proc open_project { args } {
            puts "OC_VIVADO.TCL: In OpenChip open_project wrapper"
            puts $args
            set projfile ""
            set sep [file separator]
            foreach arg $args {
                if { [string index $arg 0] != "-" } { set projfile "[pwd]$sep$arg" }
            }
            oc_open_project_original {*}$args
            if { $projfile == "" } {
                puts "OC_VIVADO.TCL: Didn't get a project as argument to open_project?  Not loading oc_vivado.tcl"
            } else {
                puts "projfile = $projfile"
                set oc_vivado_tcl_path [file normalize  "[file dirname $projfile]${sep}..${sep}..${sep}bin${sep}oc_vivado.tcl"]
                puts "oc_vivado_tcl_path = $oc_vivado_tcl_path"
                if [file exists "$oc_vivado_tcl_path"] {
                    puts "OC_VIVADO.TCL: Detected OpenChip project, sourcing $oc_vivado_tcl_path"
                    source $oc_vivado_tcl_path
                } else {
                    puts "OC_VIVADO.TCL: Doesn't appear to be OpenChip project, no $oc_vivado_tcl_path to source"
                }
            }
        }
    }
    set oc_hook_vivado_open_project_done 1
}

proc oc_hook_vivado {} {
    global oc_hook_vivado_done
    global oc_set_build_defines_done
    # we only want to do this once
    if { ![info exists oc_hook_vivado_done] } {
        rename launch_simulation oc_launch_simulation_original
        rename launch_runs oc_launch_runs_original
    }
    proc launch_simulation { args } {
        global oc_set_build_defines_done
        puts "OC_VIVADO.TCL: In launch_simulation wrapper"
        if { ![info exists oc_set_build_defines_done] } { oc_set_build_defines }
        oc_launch_simulation_original {*}$args
    }
    proc launch_runs { args } {
        global oc_set_build_defines_done
        puts "OC_VIVADO.TCL: In launch_runs wrapper"
        set doing_synth 0
        foreach arg $args {
            if {[regexp {synth.*} $arg match]} { set doing_synth 1 }
        }
        if { $doing_synth || ![info exists oc_set_build_defines_done] } { oc_set_build_defines }
        oc_launch_runs_original {*}$args
    }
    set oc_hook_vivado_done 1
}

# *******************************************
# Multirun support
# *******************************************

# this will call oc_multirun_reset the first time this code is read in.  if it's been pulled in once,
# we don't disturb the state just because the script is sourced again (instead use oc_multirun_clear/reset
# to reset state)
proc oc_multirun_init {} {
    global oc_multirun_loaded
    if { [info exists oc_multirun_loaded] } { return }
    oc_multirun_reset
    set oc_multirun_loaded 1
}

# this inits everything, and sets knobs to minimum viable values (1 seed, 1 strat)
proc oc_multirun_clear {} {
    global oc_multirun_synth_strategies
    global oc_multirun_impl_strategies
    global oc_multirun_dict
    set oc_multirun_synth_strategies {}
    set oc_multirun_impl_strategies {}
    set oc_multirun_dict [dict create]
    dict set oc_multirun_dict "synth_flow" "Vivado Synthesis 2021" ; # I think this can let one use algs from previous revs?
    dict set oc_multirun_dict "impl_flow" "Vivado Implementation 2021"
    dict set oc_multirun_dict "synth_threads" 1 ; # threads to use per synth job
    dict set oc_multirun_dict "impl_threads" 1 ; # threads to use per impl job
    dict set oc_multirun_dict "parallel_synth" 1 ; # number of parallel synth jobs
    dict set oc_multirun_dict "parallel_impl" 1 ; # number of parallel impl jobs
    dict set oc_multirun_dict "max_minutes_synth" 120 ; # longest runtime in minutes for synth
    dict set oc_multirun_dict "max_minutes_impl" 1200 ; # longest runtime in minutes for impl
    dict set oc_multirun_dict "seeds" 1 ; # number of seeds to try per synthesis
    dict set oc_multirun_dict "delete_runs" 1 ; # deletes runs at the start of oc_multirun
    lappend oc_multirun_synth_strategies "Default" ; # renamed Vivado Synthesis Defaults for create_runs; our naming uses this
    lappend oc_multirun_impl_strategies "Default" ; # renamed Vivado Implementation Defaults for create_runs; our naming uses this
}

# this calls oc_multirun_clear, then adds a full suite of strats, and puts reasonable seeds/parallelism for a long run
# user should turn down the values + remove unwanted strats from here, this represents "a superset" of what you probably want
proc oc_multirun_reset {} {
    global oc_multirun_synth_strategies
    global oc_multirun_impl_strategies
    global oc_multirun_dict
    oc_multirun_clear
    # most names have no whitespace so no hacky translation like Default
    lappend oc_multirun_synth_strategies "Flow_PerfOptimized_high"
    lappend oc_multirun_synth_strategies "Flow_AlternateRoutability"
    lappend oc_multirun_synth_strategies "Flow_PerfThresholdCarry"
    lappend oc_multirun_impl_strategies "Performance_Explore"
    lappend oc_multirun_impl_strategies "Performance_Retiming"
    lappend oc_multirun_impl_strategies "Performance_ExploreWithRemap"
    lappend oc_multirun_impl_strategies "Performance_ExplorePostRoutePhysOpt"
    lappend oc_multirun_impl_strategies "Performance_ExtraTimingOpt"
    dict set oc_multirun_dict "parallel_synth" 2
    dict set oc_multirun_dict "parallel_impl" 2
    dict set oc_multirun_dict "seeds" 2
}

proc oc_multirun {} {
    global oc_multirun_dict
    # delete any previous multirun runs
    if { [dict get $oc_multirun_dict "delete_runs"] } {
        delete_runs [get_runs synth_m_* -quiet] -quiet ; # will also delete impl_m_* underneath
    }
    # call the iterator
    oc_multirun_iterator
}

proc oc_multirun_iterator {} {
    global oc_multirun_dict
    global oc_multirun_synth_strategies
    global oc_multirun_impl_strategies
    global oc_multirun_start_time
    global oc_hook_vivado_done

    set oc_multirun_start_time [clock seconds]

    # *** SYNTHESIS
    set_param general.maxThreads [dict get $oc_multirun_dict "synth_threads"]
    set seeds [dict get $oc_multirun_dict "seeds"]
    set synth_strats [llength $oc_multirun_synth_strategies]
    set runs_total [ expr { $seeds * $synth_strats } ];

    set runs_launched 0

    # if launch_runs has been hooked, we will "manually" setup build defines here (UUID, build time/date, etc)
    # because changing those things later makes it look like all simulation results are out of date.
    if { [info exists oc_hook_vivado_done] } { oc_set_build_defines }

    for { set seed 1 } { $seed <= $seeds } { incr seed } {
        foreach synth_strategy $oc_multirun_synth_strategies {
            # doing the below causes all synth runs to say "out of date", which isn't great
            # could (1) create all the runs, then forcibly set them to be up to date, then launch, or
            # (2) figure out how to pass the open below via synth_design arg
            #            set_property verilog_define SYNTH_SEED=$seed [current_fileset]
            set synth_run_name synth_m_${synth_strategy}_${seed}
            if { $synth_strategy == "Default" } {
                set synth_strategy_name "Vivado Synthesis Defaults"
            } else {
                set synth_strategy_name $synth_strategy
            }
            if { [llength [get_runs $synth_run_name -quiet]] } {
                puts "INFO: $synth_run_name already exists, skipping creating the run"
            } else {
                create_run $synth_run_name \
                    -flow [dict get $oc_multirun_dict "synth_flow"] -strategy $synth_strategy_name
                set new_defines ""
                foreach d [oc_set_define_in_string [oc_get_project_defines] "TARGET_SEED=${seed}"] {
                    set dq [string map {"\"" "\\\"" } $d]
                    append new_defines "-verilog_define \"${dq}\" "
                }
                set new_defines [string trim $new_defines]
                set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value $new_defines -objects [get_runs $synth_run_name]
            }
            if { [ oc_project_is_complete $synth_run_name] } {
                puts "INFO: $synth_run_name has completed, skipping starting the run"
                incr runs_launched
            } elseif { [ oc_project_is_running $synth_run_name] } {
                puts "INFO: $synth_run_name is already running, skipping starting the run"
                incr runs_launched
            } else {
                # it's either running or we're about to start it, so let's check to see if we're ready
                set text [format "Synth, %d / %d launched" $runs_launched $runs_total]
                oc_multirun_wait_on_runs $text [dict get $oc_multirun_dict "parallel_synth"] \
                    [dict get $oc_multirun_dict "max_minutes_synth"]
                if { [info exists oc_hook_vivado_done] } { oc_launch_runs_original $synth_run_name
                } else {                                   launch_runs $synth_run_name }
                after 5000 ; # give that time to start
                incr runs_launched
            }
        }
    }
    if { $runs_launched } {
        set text [format "Synth Finishing, all %d launched" $runs_total]
        oc_multirun_wait_on_runs $text 1 [dict get $oc_multirun_dict "max_minutes_synth"]
    }

    # *** IMPLEMENTATION
    set_param general.maxThreads [dict get $oc_multirun_dict "impl_threads"]
    set seeds [dict get $oc_multirun_dict "seeds"]
    set synth_strats [llength $oc_multirun_synth_strategies]
    set impl_strats [llength $oc_multirun_impl_strategies]
    set runs_total [ expr { $seeds * $synth_strats * $impl_strats } ];
    set runs_launched 0
    for { set seed 1 } { $seed <= $seeds } { incr seed } {
        foreach synth_strategy $oc_multirun_synth_strategies {
            if { $synth_strategy == "Default" } {
                set synth_strategy_name "Vivado Synthesis Defaults"
            } else {
                set synth_strategy_name $synth_strategy
            }
            foreach impl_strategy $oc_multirun_impl_strategies {
                if { $impl_strategy == "Default" } {
                    set impl_strategy_name "Vivado Implementation Defaults"
                } else {
                    set impl_strategy_name $impl_strategy
                }
                set synth_run_name synth_m_${synth_strategy}_${seed}
                set impl_run_name impl_m_${synth_strategy}_${seed}_${impl_strategy}
                if { [llength [get_runs $impl_run_name -quiet]] } {
                    puts "INFO: $impl_run_name already exists, skipping creating the run"
                } else {
                    create_run $impl_run_name -parent_run $synth_run_name \
                        -flow [dict get $oc_multirun_dict "impl_flow"] -strategy $impl_strategy_name
                }
                if { [ oc_project_is_complete $impl_run_name] } {
                    puts "INFO: $impl_run_name has completed, skipping starting the run"
                    incr runs_launched
                } elseif { [ oc_project_is_running $impl_run_name] } {
                    puts "INFO: $impl_run_name is already running, skipping starting the run"
                    incr runs_launched
                } else {
                    set text [format "Impl, %d / %d launched" $runs_launched $runs_total]
                    oc_multirun_wait_on_runs $text [dict get $oc_multirun_dict "parallel_impl"] \
                        [dict get $oc_multirun_dict "max_minutes_impl"]
                    launch_runs $impl_run_name
                    after 5000 ; # give that time to start
                    incr runs_launched
                }
            }
        }
    }
    set text [format "Impl Finishing, all %d launched" $runs_total]
    oc_multirun_wait_on_runs $text 1 [dict get $oc_multirun_dict "max_minutes_impl"]
    puts "OC_MULTIRUN: All jobs complete, reporting..."

    oc_multirun_report
}

set oc_multirun_start_time [clock seconds]
proc oc_multirun_wait_on_runs { text max_runs max_min } {
    global oc_multirun_start_time
    set poll_s 10
    set info_s 120
    set seconds 0
    set info_seconds -1
    set running [oc_multirun_running]
    while { $running >= $max_runs } {
        set minutes [expr { $seconds / 60 }]
        set totalminutes [expr { ([clock seconds] - $oc_multirun_start_time) / 60 }]
        set waittext "MULTIRUN: $text, $running running"
        if { $max_runs > 1 } { append waittext [format ", waiting until < $max_runs"]
        } else { append waittext ", waiting until done" }
        if { $info_seconds == -1 } {
            puts "$waittext ($totalminutes min since start)" ; # first time through
            set info_seconds 0
        } elseif { $info_seconds >= $info_s } {
            puts "$waittext ($minutes min since last update, $totalminutes min since start)"
            set info_seconds 0
        }
        if { $minutes >= $max_min } {
            puts "MULTIRUN: $text, TIMEOUT ERROR after $minutes minutes since update, exiting..."
            break
        }
        after [expr { $poll_s * 1000 }]
        incr seconds $poll_s
        incr info_seconds $poll_s
        set running [oc_multirun_running]
    }
}

proc oc_project_is_running { run } {
    set status [get_property STATUS [get_runs $run]]
    if { ( [string first "Running" $status ] != -1) || ( [string first "Queued" $status ] != -1) } {
        return 1
    } else { return 0 }
}

proc oc_project_is_complete { run } {
    set progress [get_property PROGRESS [get_runs $run]]
    if { ($progress == "100%") } {
        return 1
    } else { return 0 }
}

proc oc_multirun_running {} {
    set running 0
    foreach run [get_runs impl_m_* -quiet] {
        incr running [oc_project_is_running $run]
    }
    foreach run [get_runs synth_m_* -quiet] {
        incr running [oc_project_is_running $run]
    }
    return $running
}

proc oc_multirun_report {} {
    global oc_multirun_dict
    global oc_multirun_synth_strategies
    global oc_multirun_impl_strategies

    puts "OC_MULTIRUN_REPORT: Standalone reporting, please make sure seeds and strategies match what was run..."

    puts ""
    puts "*** REPORTING ALL RUNS ***"
    for { set seed 1 } { $seed <= [dict get $oc_multirun_dict "seeds"] } { incr seed } {
        foreach synth_strategy $oc_multirun_synth_strategies {
            foreach impl_strategy $oc_multirun_impl_strategies {
                set impl_run_name impl_m_${synth_strategy}_${seed}_${impl_strategy}
                set stat_dict [oc_multirun_get_stats $impl_run_name]
                oc_multirun_print_stat_dict $stat_dict
            }
        }
    }

    puts ""
    puts "*** REPORTING ACROSS SEEDS ***"
    foreach synth_strategy $oc_multirun_synth_strategies {
        foreach impl_strategy $oc_multirun_impl_strategies {
            set stat_range [oc_multirun_create_stat_range]
            for { set seed 1 } { $seed <= [dict get $oc_multirun_dict "seeds"] } { incr seed } {
                set impl_run_name impl_m_${synth_strategy}_${seed}_${impl_strategy}
                set stat_dict [oc_multirun_get_stats $impl_run_name]
                oc_multirun_stat_merge stat_range stat_dict
            }
            oc_multirun_print_stat_range impl_m_${synth_strategy}_x_${impl_strategy} $stat_range
        }
    }

    puts ""
    puts "*** REPORTING ACROSS SYNTH STRATEGIES ***"
    foreach synth_strategy $oc_multirun_synth_strategies {
        set stat_range [oc_multirun_create_stat_range]
        foreach impl_strategy $oc_multirun_impl_strategies {
            for { set seed 1 } { $seed <= [dict get $oc_multirun_dict "seeds"] } { incr seed } {
                set impl_run_name impl_m_${synth_strategy}_${seed}_${impl_strategy}
                set stat_dict [oc_multirun_get_stats $impl_run_name]
                oc_multirun_stat_merge stat_range stat_dict
            }
        }
        oc_multirun_print_stat_range impl_m_${synth_strategy}_x_x $stat_range
    }

    puts ""
    puts "*** REPORTING ACROSS IMPL STRATEGIES ***"
    foreach impl_strategy $oc_multirun_impl_strategies {
        set stat_range [oc_multirun_create_stat_range]
        foreach synth_strategy $oc_multirun_synth_strategies {
            for { set seed 1 } { $seed <= [dict get $oc_multirun_dict "seeds"] } { incr seed } {
                set impl_run_name impl_m_${synth_strategy}_${seed}_${impl_strategy}
                set stat_dict [oc_multirun_get_stats $impl_run_name]
                oc_multirun_stat_merge stat_range stat_dict
            }
        }
        oc_multirun_print_stat_range impl_m_x_x_${impl_strategy} $stat_range
    }
}

proc oc_multirun_print_stat_dict { d } {
    if { [dict get $d error] } {
        puts [format "%-70s WNS:------- TNS:--------- WHS:------- THS:--------- POWER:----- MINUTES:%5.1f (ERROR)" \
                  [dict get $d run] [dict get $d minutes] ]
    } else {
        puts [format "%-70s WNS:%7.3f TNS:%9.1f WHS:%7.3f THS:%9.1f POWER:%5.2f MINUTES:%5.1f" \
                  [dict get $d run] [dict get $d wns] [dict get $d tns] \
                  [dict get $d whs] [dict get $d ths] [dict get $d power] [dict get $d minutes] ]
    }
}

proc oc_multirun_print_stat_range { text r } {
    puts [format "%-70s WNS:%7.3f/%7.3f/%7.3f TNS:%9.1f/%9.1f/%9.1f WHS:%7.3f THS:%9.1f POWER:%5.2f-%5.2f MINUTES:%5.1f-%5.1f ERRORS:%3.0f%%" \
              $text \
              [dict get $r wns_min] [dict get $r wns_average] [dict get $r wns_max] \
              [dict get $r tns_min] [dict get $r tns_average] [dict get $r tns_max] \
              [dict get $r whs_min] [dict get $r ths_min] \
              [dict get $r power_min] [dict get $r power_max] \
              [dict get $r minutes_min] [dict get $r minutes_max] \
              [dict get $r error_percent] ]
}

proc oc_multirun_create_stat_range {} {
    set stat_range_dict [dict create]
    foreach token { wns tns whs ths power minutes } {
        dict set stat_range_dict ${token}_max -9999999999
        dict set stat_range_dict ${token}_min 9999999999
        dict set stat_range_dict ${token}_average 0
        dict set stat_range_dict ${token}_total 0
    }
    dict set stat_range_dict count 0
    dict set stat_range_dict passing 0
    dict set stat_range_dict errors 0
    dict set stat_range_dict error_percent 0
    return $stat_range_dict
}

proc oc_multirun_stat_merge { stat_range_var stat_dict_var } {
    upvar 1 $stat_range_var stat_range
    upvar 1 $stat_dict_var stat_dict
    dict incr stat_range count 1
    if { [dict get $stat_dict error] } {
        dict incr stat_range errors 1
    } else {
        dict incr stat_range passing 1
        foreach token { wns tns whs ths power minutes } {
            if { [dict get $stat_dict $token] > [dict get $stat_range ${token}_max] } {
                dict set stat_range ${token}_max [dict get $stat_dict $token]
            }
            if { [dict get $stat_dict $token] < [dict get $stat_range ${token}_min] } {
                dict set stat_range ${token}_min [dict get $stat_dict $token]
            }
            dict set stat_range ${token}_total \
                [expr { [dict get $stat_range ${token}_total] + [dict get $stat_dict $token] }]
            dict set stat_range ${token}_average \
                [expr { [dict get $stat_range ${token}_total] / [dict get $stat_range passing] }]
        }
    }
    dict set stat_range error_percent \
        [expr { 100.0 * [dict get $stat_range errors] / [dict get $stat_range count] }]
}

proc oc_multirun_get_stats { run } {
    set stat_dict [dict create]
    set run [get_runs $run]
    dict set stat_dict run $run
    dict set stat_dict wns [get_property STATS.WNS $run]
    dict set stat_dict tns [get_property STATS.TNS $run]
    dict set stat_dict whs [get_property STATS.WHS $run]
    dict set stat_dict ths [get_property STATS.THS $run]
    dict set stat_dict power [get_property STATS.TOTAL_POWER $run]
    set elapsed [get_property STATS.ELAPSED $run]
    dict set stat_dict minutes [oc_multirun_elapsed_to_minutes $elapsed]
    set status [get_property STATUS $run]
    dict set stat_dict status $status
    if { [string first "ERROR" $status] != -1 } {
        dict set stat_dict error 1
    } else {
        dict set stat_dict error 0
    }
    return $stat_dict
}

proc oc_multirun_elapsed_to_minutes { elapsed } {
    regexp {(\d+)\:(\d+)\:(\d+)} $elapsed fullmatch hours minutes seconds
    set minutes
    set minutes [scan $minutes %d]
    return [expr { [scan $hours %d]*60 + [scan $minutes %d] + [scan $seconds %d]/60.0 }]
}

# *******************************************
# Info about design run, path, etc
# *******************************************

# convenience function to return the type of the project (i.e. context: "gui", "synth" or "impl" currently)
proc oc_is_run { run_type } {
    if { [oc_project_type] == $run_type } { return 1 }
    return 0
}

proc oc_project_type { } {
    # this may need to get a little smarter but it works for now
    if {[regexp {.*runs\/(\w+)_\w+} [pwd] match project_type]} {
        return $project_type
    }
    return "gui"
}



# *******************************************
# Swap userspace applications
# *******************************************

# utility function -- is "target" under "root"
proc oc_is_path_within { path dir } {
    set path_norm [file normalize $path]
    set dir_norm [file normalize $dir]
    return [string match "${dir_norm}/*" "${path_norm}"]
}

# call this to report any files that dont appear to be part of the default userspace for the target
proc oc_list_outside_files {} {
    global oc_root
    global oc_projdir
    # first remove any files that are outside OC_ROOT or inside OC_ROOT/user
    foreach path [get_files] {
        if { ![oc_is_path_within $path $oc_root] } {
            puts "* OUTSIDE OC_ROOT  : ${path}"
        } elseif { [oc_is_path_within $path $oc_root/user] } {
            puts "* USERSPACE        : ${path}"
        } elseif { [oc_is_path_within $path $oc_root/target] } {
            if { ! [oc_is_path_within $path $oc_projdir] } {
                puts "* DIFFERENT TARGET : ${path}"
            }
        }
    }
}

proc oc_add_file { path fileset {existing ""}} {
    set tailpath [file tail $path]
    # remove any existing file with the same name (allows us to override chip_defines.vh etc)
    if { ($existing != "") && [dict exists $existing $tailpath] } {
        # the same filename already exists in our sources, remove it
        puts "  (removing matching file [dict get $existing $tailpath])"
        remove_files [dict get $existing $tailpath]
    }
    # add the new file from userspace
    puts "  (adding file to fileset $fileset)"
    add_files -fileset $fileset $path 
}

proc oc_unload_userspace { } {
    global oc_root
    global oc_projdir
    # restores the default oc_user into the current project
    # first remove any files from outside the openchip area, or within the userspace area
    foreach fileset_iter [get_filesets] {
        foreach file_iter [get_files -of [get_fileset $fileset_iter] -quiet] {
            if { [string first $oc_root $file_iter] != 0 } {
                # the file is outside the openchip repo, remove it
                remove_files -fileset $fileset_iter $file_iter
            } elseif { [string first "${oc_root}/user" $file_iter] == 0 } {
                # the file is from the userspace area, remove it
                remove_files -fileset $fileset_iter $file_iter
            }
        }
    }
    # now add the files for default userspace builds
    add_files -fileset sources_1 "${oc_projdir}/chip_defines.vh" -quiet
    set_property is_global_include true [get_files "${oc_projdir}/chip_defines.vh"] -quiet
    add_files -fileset sources_1 "${oc_root}/top/oc_user.sv" -quiet
    add_files -fileset sim_1 "${oc_root}/top/chip_test.sv" -quiet
    set_property top chip_test [get_filesets sim_1]
}

proc oc_load_userspace { userspace } {
    # loads a userspace app into the current project
    global oc_root
    global oc_projname
    set user_dir "${oc_root}/user/${userspace}"
    # build a dictionary of all the filenames we already have
    set file_dict [dict create]
    foreach path [get_files] {
        dict set file_dict [file tail $path] $path
    }
    foreach path [glob -- "${user_dir}/constraints/*"] {
        puts "* Found ${path}"
        oc_add_file $path constrs_1 $file_dict
    }
    foreach path [glob -- "${user_dir}/design/*"] {
        puts "* Found ${path}"
        oc_add_file $path sources_1 $file_dict
        if { [file tail $path] == "chip_defines.vh" } {
            puts "  (because this is chip_defines.vh, setting is_global_include property)"
            set_property is_global_include true [get_files $path]
        }
    }
    foreach path [glob == "${user_dir}/sim/*"] {
        puts "* Found ${path}"
        oc_add_file $path sim_1 $file_dict
        if { [file tail $path] == "chip_test.sv" } {
            puts "  (because this is chip_test.sv, setting chip_test as top for sim_1)"
            set_property top chip_test [get_filesets sim_1]
        }
    }
}

# *******************************************
# Setup globals
# *******************************************

proc oc_find_root { } {
    set oc_root [file normalize [get_property DIRECTORY [current_project]]]
    set done 0
    while { ! $done } {
        set oc_root [file dirname $oc_root]
        if { [file exists "$oc_root/.oc_root"] } {
            set done 1
        } elseif { $oc_root == "/" } {
            puts "OC_VIVADO.TCL: ERROR: Couldn't find oc_root!"
            set oc_root $oc_projdir
            set done 1
        }
    }
    return $oc_root
}

if { [current_project -quiet] == "" } {
    puts "OC_VIVADO.TCL: No project open yet, hooking open_project command to source oc_vivado again"
    # we don't have a project loaded, probably Vivado_init.tcl has pulled us in very early, we just do minimal
    # hooking of open_project so that it sources us again when a project is opened
    oc_hook_vivado_open_project
} else {
    if { [oc_is_run "gui"] } {
        puts "OC_VIVADO.TCL: Project open in GUI, assuming target dir is the current open project's directory"
        set oc_projdir  [file normalize [get_property DIRECTORY [current_project]]]
        set oc_root [oc_find_root]
        set oc_projname [get_property NAME [current_project]]
    } else {
        # this is synth/impl and will be in <root>/targets/<board>/<board>.runs/synth_1 or equiv
        puts "OC_VIVADO.TCL: Project not open in GUI, assuming actual target dir is two levels above current open synth/impl project"
        set oc_projdir  [file normalize [get_property DIRECTORY [current_project]]/../..]
        set oc_root [oc_find_root]
        set oc_projname [file rootname [file tail [file normalize [get_property DIRECTORY [current_project]]/..]]]
    }

    puts "OC_VIVADO.TCL: oc_root     = $oc_root"
    puts "OC_VIVADO.TCL: oc_projdir  = $oc_projdir"
    puts "OC_VIVADO.TCL: oc_projname = $oc_projname"

    # this will check whether it's been run already, so it doesn't hook same proc multiple times
    # that "run only once" check could be moved down here if we find other things that we only want done once
    oc_hook_vivado
    # similar story, since we don't want to lose user configuration just because the script is reloaded
    oc_multirun_init
}


# this is messy but older versions of vivado dont have this command
if { ! [llength [info commands wait_on_runs]] } {
    proc wait_on_runs { runs } {
        puts "OC_VIVADO: custom implementation of wait_on_runs for older Vivado"
        foreach r $runs {
            puts "OC_VIVADO: waiting on run $r ..."
            wait_on_run $r
        }
    }
}

puts "OC_VIVADO.TCL: DONE"


# it is recommended that the user places the following in a Vivado_init.tcl file:
#set oc_vivado_tcl [file normalize "[pwd]/../../bin/oc_vivado.tcl"]
#if { [file exists $oc_vivado_tcl] } {
#    puts "VIVADO_INIT.TCL: OpenChip workspace detected, sourcing $oc_vivado_tcl"
#    source $oc_vivado_tcl
#}
