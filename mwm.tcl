#!/usr/bin/env tclsh

set main_target "main"
set cd_dir "."
set mwm_file mwmfile.tcl
set g_verbose 0

proc p_usage {} {
	puts "$::argv0 usage:
    --cd <path>
        Changes to <path> before executing commands.
    --file <other-mwmfile.tcl>
        Source targets from <other-mwmfile.tcl> instead of mwmfile.tcl
    --target <main-target>
        Build this target instead of \"$main_target\"
        "
}

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
		--target {
			incr i
            if {$argc == $i} {
                error "No target provided for --target"
            }
			set main_target [lindex $argv $i]
        }
		--file {
			incr i
            if {$argc == $i} {
                error "No file provided for --file"
            }
			set mwm_file [lindex $argv $i]
        }
        --verbose {
            set g_verbose 1
		}
		default { error "Unrecognized arg $arg!" }
    }
}

# Store values in a {up-to-date inputs outputs}
set g_targets [dict create]

proc make_target {name outputs inputs command} {
    global g_targets
    if {[dict exists $g_targets $name]} {
        error "$name is already a target!"
    }
    set add_val [list 0 $outputs $inputs $command]
    global g_verbose
    if {$g_verbose} {
        puts "Adding target $name with these values ($add_val)"
    }
    dict set g_targets $name $add_val
}

if {[file isdirectory $cd_dir] == 0} {
    error "$cd_dir does not exist or is not a folder!"
}
cd $cd_dir

if {[file isfile $mwm_file] == 0} {
    error "$mwm_file does not exist or is not a file!"
}
source $mwm_file

# This file holds the lengths for each file.
set data_file .mwmdata.tsv
set g_f_lens [dict create]
if {[file exists $data_file]} {
    # This should update g_f_lens
    set data_f [open $data_file r]
    while {[gets $data_f line] >= 0} {
        # TODO: Use a regex?
        set len_start [string last "\t" $line]
        set len [string range $line $len_start+1 end]
        set f_name [string range $line 0 $len_start-1]
        dict set g_f_lens $f_name $len
    }
    close $data_f
}

# TODO: Optimize for multithreading.
proc update_target {t_name} {
    global g_targets
    if {[dict exists $g_targets $t_name] == 0} {
        error "Target $t_name does not exist!"
    }
    set t_info [dict get $g_targets $t_name]

    global g_verbose
    set inputs [lindex $t_info 2]
    set up_to_date 1
    foreach input $inputs {
        if {[file isfile $input]} {
            if {[dict exists $g_f_lens $input]} {
                set f_len [dict get $g_f_lens $input]
                set f_size [file size $input]
                if {[string compare $f_len $f_size] != 0} {
                    if {$g_verbose} {
                        puts "$input is out of date old len=$f_len, new len=$f_size"
                    }
                    set up_to_date 0
                    break
                }
            } else {
                # The file did not exist before.
                set up_to_date 0
                break
            }
        } elseif {[file isdirectory $input]} {
            if {$g_verbose} {
                puts "\"$input\" is a folder, skipping"
            }
        } elseif {[dict exists $g_targets $input]} {
            if {$g_verbose} {
                puts "Updating \"$input\" for \"$t_name\""
            }
            update_target $input
        } else {
            error "$input for target \"$t_name\" is not a file or a target!"
        }
    }
    if {$up_to_date == 0 || [llength $inputs] == 0} {
        set command [lindex $t_info 3]
        if {$g_verbose} {
            puts "Running $command for $t_name"
        }
        # Assume the file is an output of the command.
        if {[llength [info procs $command]] == 1} {
            # Run this TCL proc
            $command
        } else {
            exec >@stdout 2>@stderr {*}$command
        }
        global g_f_lens
        foreach output [lindex $t_info 1] {
            if {[file exists $output] == 0} {
                error "Output \"$output\" does not exist after an update!"
            } elseif {[file isfile $output]} {
                set new_sz [file size $output]
                if {$g_verbose} {
                    puts "Updating size for \"$output\" to $new_sz"
                }
                dict set g_f_lens $output $new_sz
            } 
        }
    }
}

update_target $main_target

if {[dict size $g_f_lens] > 0} {
    if {$g_verbose} {
        puts "Updating $data_file with new lengths"
    }
    set data_f [open $data_file w]
    dict for {f_name sz} $g_f_lens {
        puts $data_f "$f_name\t$sz"
    }
    close $data_f
}
