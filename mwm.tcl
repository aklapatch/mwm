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

# Store values in a {up-to-date updated inputs outputs command} format
set g_targets [dict create]

proc make_target {name outputs inputs command} {
    global g_targets
    if {[dict exists $g_targets $name]} {
        error "$name is already a target!"
    }
    set add_val [list 0 0 $outputs $inputs $command]
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

# Get all the targets we need to update values for (to add to the cache).
set depended_targets [list]

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

# TODO: Switch to an algorithm that:
# - Finds all the input files that feed into a target
# - See if they're out of date
# - Then build the right targets to update those files
# This should be more of a loop, and less recursive.
# This may help with multithreading too, but I'm unsure of that.
# My cache test has a problem where one target updates an ouput, but that output does not change between
# target runs. I need a way to detect when an output file changes to another target, but to not rebuild
# if it stays the sam.e That may involve building the input target, then checking if the output file is different.
# That sounds involved.
# Another issue is that the target that makes the file always runs. That mans we cannot tell to update other targets by checking if this target updated or not.

# TODO: Optimize for multithreading.
proc update_target {t_name depth} {
    global g_targets
    if {[dict exists $g_targets $t_name] == 0} {
        error "Target $t_name does not exist!"
    }
    set t_info [dict get $g_targets $t_name]

    global g_verbose
    set inputs [lindex $t_info 3]
    set up_to_date 1
    # TODO: removed redundant input checking, or at least issue a warning.
    set input_f_lens [dict create]
    foreach input $inputs {
        if {[file isfile $input]} {
            set f_new_size [file size $input]
            set new_f_hash [hash_file $input]
            if {[dict exists $g_f_lens $input]} {
                set f_meta [dict get $g_f_lens $input]
                set f_len [lindex $f_meta 0]
                set f_hash [lindex $f_meta 1]
                if {[string compare $f_len $f_new_size] != 0} {
                    if {$g_verbose} {
                        puts "$input is out of date old len=$f_len, new len=$f_size"
                    }
                    set up_to_date 0
                }
                if {[string compare $new_f_hash $f_hash] != 0} {
                    if {$g_verbose} {
                        puts "$input is out of date old hash=$f_hash, new hash=$new_f_hash"
                    }
                    set up_to_date 0
                }
            } else {
                # This is a new file.
                set up_to_date 0
            }
            # It's important that this only is written to the cache if the command succeeds.
            # Otherwise, we will have a problem.
            dict set g_f_lens $input [list $f_new_size $new_f_hash]
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
                # Pass in the depth so the target can know it should update it's outputs in the cache.
                update_target $input [expr $depth + 1]
            }
            # Get info again because it may have udpated.
            set in_info [dict get $g_targets $input]
            set in_updated [lindex $in_info 1]
            if {$in_updated} {
                # Our target updated, we should too.
                if {$g_verbose} {
                    puts "Target $input is out of date, rebuilding!"
                }
                set up_to_date 0
            }
        } else {
            error "$input for target \"$t_name\" is not a file or a target!"
        }
    }
    if {$up_to_date == 0 || [llength $inputs] == 0} {
        set command [lindex $t_info 4]
        if {$g_verbose} {
            puts "Running \"$command\" for target \"$t_name\""
        }
        # Get the time in case this is a folder. We can tell if it's created by the mtime.
        set start_time [clock seconds]
        # Assume the file is an output of the command.
        if {[llength [info procs $command]] == 1} {
            # Run this TCL proc
            $command
        } else {
            exec >@stdout 2>@stderr {*}$command
        }
        global g_f_lens
        foreach output [lindex $t_info 2] {
            if {[file exists $output] == 0} {
                error "Output \"$output\" from target \"$t_name\" does not exist after an update!"
            } 
            if {$depth > 0} {
                # Only say we've updated if our outputs changed
                if  {[file isfile $output]} { 
                    set f_new_size [file size $output]
                    set new_f_hash [hash_file $output]

                    if {[dict exists $g_f_lens $output]} {
                        set out_info [dict get $g_f_lens $output]
                        set f_sz [lindex $out_info 0]
                        set f_hash [lindex $out_info 1]
                        if {[string compare $f_sz $f_new_size] != 0} {
                            if {$g_verbose} {
                                puts "$output changed. old len=$f_sz, new len=$f_new_size"
                            }
                            # Let other targets know we updated so they can update too.
                            lset t_info 1 1
                        }
                        if {[string compare $new_f_hash $f_hash] != 0} {
                            if {$g_verbose} {
                                puts "$output changed. old hash=$f_hash, new hash=$new_f_hash"
                            }
                            # Let other targets know we updated so they can update too.
                            lset t_info 1 1
                        }
                    } else {
                        if {$g_verbose} {
                            puts "$output was not in cache, we're out of date."
                        }
                        # We were missing an entry, so we're definitely out of date.
                        lset t_info 1 1
                    }
                    dict set g_f_lens $output [list $f_new_size $new_f_hash]
                } elseif {[file isdirectory $output]} {
                    set dir_time [file mtime $output]
                    if {$dir_time >= $start_time} {
                        # The folder was created, we are out of date.
                        if {$g_verbose} {
                            puts "$output was there before, we're out of date."
                        }
                        lset t_info 1 1 
                    }
                }
            }
        }
    }
    # Use the global targets to let every other target know we're up to date now.
    lset t_info 0 1
    if {$g_verbose} {
        puts "Updating target data with $t_info"
    }
    dict set g_targets $t_name $t_info
}

update_target $g_main_target 0

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
