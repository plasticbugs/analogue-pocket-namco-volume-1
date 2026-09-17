cd projects
project_open ncv1_pocket -revision ncv1_pocket
create_timing_netlist -model slow
read_sdc
update_timing_netlist
set paths [get_timing_paths -setup -npaths 200 -nworst 200]
array set src {}
array set dst {}
foreach_in_collection p $paths {
    set s [get_path_info $p -slack]
    if {$s < 0} {
        set f [get_node_info [get_path_info $p -from] -name]
        set t [get_node_info [get_path_info $p -to] -name]
        regsub {.*\|} $f "" f2; regsub {\[.*} $f2 "" f2
        regsub {.*\|} $t "" t2; regsub {\[.*} $t2 "" t2
        incr src($f2); incr dst($t2)
    }
}
puts "=== FAILING PATH SOURCES ==="
foreach k [array names src] { puts "  src $k  x$src($k)" }
puts "=== FAILING PATH DESTS ==="
foreach k [array names dst] { puts "  dst $k  x$dst($k)" }
delete_timing_netlist
project_close
