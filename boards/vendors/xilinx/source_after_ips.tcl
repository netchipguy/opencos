
# SPDX-License-Identifier: MPL-2.0

puts "LAUNCHING IP RUNS: ${ip_run_list}"
launch_runs ${ip_run_list} -jobs ${parallel_jobs}
puts "WAITING FOR IP RUNS: ${ip_run_list}"
wait_on_runs ${ip_run_list}

foreach xci_file ${xci_file_list} {
    puts "EXPORTING IP: ${xci_file}"
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
puts "DONE IP GENERATION"
