cd projects
project_open ncv1_pocket -revision ncv1_pocket
create_timing_netlist -model fast
read_sdc
update_timing_netlist
set paths [get_timing_paths -hold -npaths 6 -nworst 6]
foreach_in_collection p $paths {
    puts "HOLD [format %.3f [get_path_info $p -slack]]  [get_node_info [get_path_info $p -from] -name]  ->  [get_node_info [get_path_info $p -to] -name]"
}
delete_timing_netlist
project_close
