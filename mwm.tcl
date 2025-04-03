#!/usr/bin/env tclsh

set g_main_target "main"
set g_cd_dir "."
set g_mwm_file mwmfile.tcl
# This file holds the data for each file we depend on.
# .tcld mean TCL Dictionary
set g_data_file .mwmdata.tcld
set g_verbose 0

proc p_usage {} {
    global g_data_file g_main_target g_mwm_file
	puts "$::argv0 usage:
    --cd <path>
        Changes to <path> before executing commands.
    --target <main-target>
        Build this target instead of \"$g_main_target\"
    --file <other-mwmfile.tcl>
        Source targets from <other-mwmfile.tcl> instead of \"$g_mwm_file\"
    --data-file <other-mwmdata.tcld>
        Get file data from <other-mwmdata.tcld> instead of \"$g_data_file\"
    --verbose
        Print more information messages while running.
        "
}

for {set i 0} {$i < $argc} {incr i} {
	set arg [lindex $argv $i]
	switch $arg {
        -h - 
        --help { 
            p_usage
            exit 0
        } --cd { 
			incr i
            if {$argc == $i} {
                error "No folder provided for --cd"
            }
			set g_cd_dir [lindex $argv $i]
        } --target {
			incr i
            if {$argc == $i} {
                error "No target provided for --target"
            }
			set g_main_target [lindex $argv $i]
        } --file {
			incr i
            if {$argc == $i} {
                error "No file provided for --file"
            }
			set mwm_file [lindex $argv $i]
        } --data-file {
            incr i
            if {$argc == $i} {
                error "No file provided for --data-file"
            }
            set g_data_file [lindex $argv $i]
        } --verbose {
            set g_verbose 1
		} default { 
            p_usage
            error "Unrecognized argument \"$arg\"!" 
        }
    }
}

# Store values in a {up-to-date inputs outputs} format
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

if {[file isdirectory $g_cd_dir] == 0} {
    error "$g_cd_dir does not exist or is not a folder!"
}
cd $g_cd_dir

if {[file isfile $mwm_file] == 0} {
    error "$mwm_file does not exist or is not a file!"
}
source $mwm_file

set g_f_lens [dict create]
if {[file exists $g_data_file]} {
    set data_f [open $g_data_file r]
    set f_text [read $data_f]
    close $data_f
    set g_f_lens [dict create {*}$f_text]
    if {$g_verbose} {
        puts "File data from $g_data_file:\n$g_f_lens"
    }
} else {
    puts "Data file $g_data_file is missing, skipping it"

}

proc hash_file {f_path} {
    set read_sz 8
    # The golden ratio, 64 bit.
    set state 0x9e3779b97f4a7c13
    if {[file size $f_path] == 0} {
        return $state
    }
    set f_h [open $f_path rb]
    while {1} {
        set rd [read $f_h $read_sz]
        foreach char [split $rd ""] {
           set char_int [scan $char %c]
           set state [expr $state + $char_int]
        }
        # Mixing function from https://jonkagstrom.com/mx3/mx3_rev2.html.
        set state [expr $state ^ ($state >> 32)]
        set state [expr $state * 0xe9846af9b1a615d]
        set state [expr $state ^ ($state >> 32)]
        set state [expr $state * 0xe9846af9b1a615d]
        set state [expr $state ^ ($state >> 28)]
        set state [expr $state & 0xffffffffffffffff]
        if {[eof $f_h]} { break }
    }
    close $f_h
    return $state
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
    # TODO: removed redundant input checking, or at least issue a warning.
    foreach input $inputs {
        if {[file isfile $input]} {
            if {[dict exists $g_f_lens $input]} {
                set f_meta [dict get $g_f_lens $input]
                set f_len [lindex $f_meta 0]
                set f_hash [lindex $f_meta 1]
                set f_new_size [file size $input]
                if {[string compare $f_len $f_new_size] != 0} {
                    if {$g_verbose} {
                        puts "$input is out of date old len=$f_len, new len=$f_size"
                    }
                    set up_to_date 0
                    dict set $g_f_lens
                }
                set new_f_hash [hash_file $input]
                if {[string compare $new_f_hash $f_hash] != 0} {
                    if {$g_verbose} {
                        puts "$input is out of date old hash=$f_hash, new hash=$new_f_hash"
                    }
                    set up_to_date 0
                    break
                }
                # Update the data  while we're here.
                # Do it before the command runs.
                # If we do it after, then we may not detect some changes to the file.
                if {$g_verbose} {
                    puts "Adding len $f_len and hash $f_hash to data for \"$input\""
                }
                dict set g_f_lens $input [list $f_len $f_hash]
            } else {
                set up_to_date 0
                # The file is not in our data, put it in.
                set f_len [file size $input]
                set f_hash [hash_file $input]
                if {$g_verbose} {
                    puts "Adding len $f_len and hash $f_hash to data for \"$input\""
                }
                dict set g_f_lens $input [list $f_len $f_hash]
            }
        } elseif {[file isdirectory $input]} {
            if {$g_verbose} {
                puts "\"$input\" is a folder, skipping"
            }
        } elseif {[dict exists $g_targets $input]} {
            if {$g_verbose} {
                puts "Updating \"$input\" for \"$t_name\""
            }
            set in_info [dict get $g_targets $input]
            set in_up_to_date [lindex $in_info 0]
            if {$in_up_to_date == 0} {
                # Avoid checking input targets many times if they're already updated.
                update_target $input
            }
        } else {
            error "$input for target \"$t_name\" is not a file or a target!"
        }
    }
    if {$up_to_date == 0 || [llength $inputs] == 0} {
        set command [lindex $t_info 3]
        if {$g_verbose} {
            puts "Running \"$command\" for target \"$t_name\""
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
                error "Output \"$output\" from target \"$t_name\" does not exist after an update!"
            }
        }
    }
    lset t_info 0 1
    # Use the global targets to let every other target know we're up to date now.
    dict set g_targets $t_name $t_info
}

update_target $g_main_target

if {[dict size $g_f_lens] > 0} {
    if {$g_verbose} {
        puts "Writing cache entries to $g_data_file: \"$g_f_lens\""
    }
    set data_f [open $g_data_file w]
    # Because everything is a string, we can just dump this to a file.
    puts $data_f $g_f_lens
    close $data_f
} else {
    puts "No file data found, skipping dump to \"$g_data_file\""
}
