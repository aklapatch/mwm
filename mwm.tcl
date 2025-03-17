#!/usr/bin/env tclsh

proc p_usage {} {
	puts "$::argv0 usage:
    --cd <path>
        Changes to <path> before executing commands.
    --file <other-mwmfile.tcl>
        Source targets from <other-mwmfile.tcl> instead of mwmfile.tcl
        "
}

set cd_dir "."
set mwm_file mwmfile.tcl
set verbose 0

for {set i 0} {$i < $argc} {incr i} {
	set arg [lindex $argv $i]
	switch $arg {
        -h - 
        --help { 
            p_usage
            exit 0
        }
        --cd { 
			incr i
            if {$argc == $i} {
                error "No folder provided for --cd"
            }
			set cd_dir [lindex $argv $i]
        }
		--file {
			incr i
            if {$argc == $i} {
                error "No file provided for --file"
            }
			set mwm_file [lindex $argv $i]
        }
        --verbose {
            set verbose 1
		}
		default { error "Unrecognized arg $arg!" }
    }
}

# Store values in a {up-to-date inputs outputs}
set g_targets [dict create]

proc make_target {name inputs outputs} {
    global g_targets
    if {[dict exists $g_targets $name]} {
        error "$name is already a target!"
    }
    set add_val {0 $inputs $outputs}
    dict set g_targets $name $add_val
    if {$verbose} {
        puts "Adding target $name with these values $add_val"
    }
}

if {[file isdirectory $cd_dir] == 0} {
    error "$cd_dir does not exist or is not a folder!"
}
cd $cd_dir

if {[file isfile $mwm_file] == 0} {
    error "$mwm_file does not exist or is not a file!"
}
source $mwm_file
