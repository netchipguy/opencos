# oc_vivado.tcl

Path: `<oc_root>/boards/vendors/xilinx/oc_vivado.tcl`

This TCL file provides many services for OpenCOS in the Xilinx Vivado tool. 

## Contexts 

The `oc_vivado.tcl` file is designed to be sourced in a variety of contexts,  adapting what actions it takes depending on context.  The supported contexts are:

- Sourced into a new instance of Vivado, before a project is opened.  This may occur because it was sourced via command line, or via `Vivado_init.tcl` file in the Vivado install.  Doing so enables the `oc_vivado.tcl` to assist opening the project, etc, but is generally not required.  When sourced this way, much of the setup cannot be done during sourcing (for example, setting `oc_projdir`, `oc_projname`).  Therefore, the `open_project` TCL proc is hooked, such that `oc_vivado.tcl` is sourced again automatically when a project is opened.
- Sourced after a project is created/opened.  This may be done via the  `open_project` TCL hook, or via TCL console, or via TCL script being run to create the project.  In this context, the `launch_runs` and similar commands are hooked, to provide updated build timestamps, etc. 
- Sourced as a constraint file during synthesis/implementation.  This this case the TCL is added into the constraint fileset.  Since each run launches a separate Vivado subprocess, `oc_vivado.tcl` must be resourced into those new processes.  This is important for automatic constraints, updating build timestamps, etc.  

## Throwing Warnings

See TCL proc `oc_throw_warning`

When TCL runs into errors, it can either crash the whole process, or send the output to STDOUT.  The latter is almost guaranteed to be missed, given the typical quantity of output.  Vivado collects it's own Info, Warning, Errors into the GUI. 

OpenCOS takes a hacky but effective approach, of attempting to access a non-existent pin (which throws a warning into the Vivado log).  The pin named such that the reason for the notification is clear (i.e. it may indicate a missing clock definition and give the clock name:  via searching for pin `OC_ADD_CLOCK_WARNING_clockTest_DOESNT_EXIST`)

## Constraints

See TCL procs starting with `oc_add_clock`

There are three basic types of constraint assistence: 

- Easing declaration (like `oc_add_clock`) by finding pins, failing safely where possible, etc. 
- Automatic constraint inclusion (like `oc_auto_scoped_xdc` ) which search the design for _modules_ and pull in matching scoped XDC files
- Automatic constraint inclusion (like `oc_auto_max_delay` ) which search the design for _attributes_ and infer constraints.  This is the preferred method of constraining, and used especially in clock-crossing libraries (`oclib_synchronizer`, etc)

## Design Exploration

See TCL procs starting with `oc_get_instances`

Various TCL procs for finding instances, net drivers, load pins, etc. 

## Define Manipulation

See TCL procs starting with `oc_set_define_in_string`

Various TCL procs for manipulating "define strings" that contain defines (adding defines, removing defines, overwriting existing define with same name, etc). 

Also tasks to load define strings from the project, and save them back to the project.  These tasks will handle setting the define in one or more file sets, etc. 

## Vivado Hooks

See TCL procs starting with `oc_hook_*`

If Vivado is opened 

## Multirun

See TCL procs starting with `oc_multirun_*`

Various TCL functions that can be called from the TCL console in Vivado to create many implementations (different seeds, synth and implementation strategies, etc).

Philosophically what this is doing is Vivado's "project mode" to leverage Vivado's ability to schedule jobs, run remote jobs, cache prior results, etc.  

For "production" usage of multirun, it's best to create a local TCL file `multirun.tcl` that is sourced from Vivado TCL console, and which captures the multirun config (strategy, number of seeds, etc). 

A more "hands-on" approach would be to call the underlying TCL functions (place_design, route_design, etc) potentially with multiple Vivado sessions for parallelism.  The lower level flow provides more control but there is a significant amount of complexity that Vivado hides (esp in the areas of IP and simulation models).  Eventually OpenCOS will have boards that are build using this lower level flow.  