# Worst setup paths on the machine clock. Run against a completed compile:
#   docker run --rm --platform linux/amd64 -v "$PWD":/build -w /build \
#       raetro/quartus:pocket quartus_sta -t projects/report_worst.tcl
# Writes output_files/worst_paths.txt next to the other reports.
cd projects
if {[catch {project_open ncv1_pocket -revision ncv1_pocket} err]} {
    puts "PROJECT OPEN FAILED: $err"; exit 1
}
create_timing_netlist -model slow
read_sdc
update_timing_netlist
set n [report_timing -setup -npaths 200 -detail full_path \
        -file output_files/worst_paths.txt]
# the SDRAM interface on its own: its paths never make the top 40 but the
# summary's dram_clk corner can still be negative
set nd [report_timing -setup -npaths 10 -detail full_path -to_clock dram_clk \
        -file output_files/worst_dram.txt]
puts "dram_clk paths returned: $nd"
puts "report_timing returned: $n"
# worst setup paths ending in each block, so one failing block cannot hide the others
set fh [open output_files/worst_by_module.txt w]
foreach m {h8300h_core h8300h h83002 ncv1_sub fx68k ncv1_main ygv608_render ygv608 c352 rom_cache shared_ram at28c16 clk_enables ncv1_core ncv1_mem sdram_ctrl dbg_overlay core_top} {
    set paths [get_timing_paths -setup -npaths 3 -to [get_keepers "*|${m}:*|*"]]
    foreach_in_collection p $paths {
        puts $fh [format "%-14s %8.3f  %s -> %s" $m [get_path_info $p -slack] \
            [get_node_info -name [get_path_info $p -from]] [get_node_info -name [get_path_info $p -to]]]
    }
}
close $fh
report_clocks -file output_files/clocks.txt
report_sdc    -file output_files/sdc_applied.txt
set nh [report_timing -hold -npaths 10 -detail full_path \
        -file output_files/worst_hold.txt]
puts "hold returned: $nh"
# the cold slow corner has its own critical paths (a 0.4 ns hot-corner path
# has missed by 0.1 there); report it too
foreach_in_collection op [get_available_operating_conditions] {
    if {[string match "*0C*" [get_operating_conditions_info $op -display_name]]} {
        set_operating_conditions $op
        update_timing_netlist
        set nc [report_timing -setup -npaths 40 -detail full_path \
                -file output_files/worst_paths_cold.txt]
        puts "cold-corner paths returned: $nc"
    }
}
delete_timing_netlist
project_close
